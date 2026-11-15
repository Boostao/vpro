package lifecycle

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
)

var helpBundleJSON = resources.HelpBundleJSON

const whatsNewConfigKey = "last_seen_whats_new_version"

type HelpCodeOption struct {
	Code  string `json:"code"`
	Label string `json:"label"`
}

type HelpFieldTopic struct {
	ID        string           `json:"id"`
	Code      string           `json:"code"`
	Section   string           `json:"section"`
	Title     string           `json:"title"`
	Column    string           `json:"column"`
	Unit      string           `json:"unit"`
	LMH25Page int              `json:"lmh25Page"`
	KeyRef    string           `json:"keyRef,omitempty"`
	Summary   string           `json:"summary"`
	Rules     []string         `json:"rules"`
	Codes     []HelpCodeOption `json:"codes"`
}

type HelpDecisionStep struct {
	Step   int    `json:"step"`
	Prompt string `json:"prompt"`
	Yes    string `json:"yes,omitempty"`
	No     string `json:"no,omitempty"`
}

type HelpDecisionKey struct {
	ID        string             `json:"id"`
	Code      string             `json:"code"`
	Title     string             `json:"title"`
	LMH25Page int                `json:"lmh25Page"`
	Steps     []HelpDecisionStep `json:"steps"`
}

type HelpGuideSection struct {
	Heading string `json:"heading"`
	Body    string `json:"body"`
}

type HelpGuide struct {
	ID       string             `json:"id"`
	Slug     string             `json:"slug"`
	Category string             `json:"category"`
	Title    string             `json:"title"`
	Summary  string             `json:"summary"`
	Sections []HelpGuideSection `json:"sections"`
}

type HelpTourStep struct {
	Target string `json:"target"`
	View   string `json:"view"`
	Title  string `json:"title"`
	Body   string `json:"body"`
}

type HelpTour struct {
	ID          string         `json:"id"`
	Title       string         `json:"title"`
	Duration    string         `json:"duration"`
	Description string         `json:"description"`
	Steps       []HelpTourStep `json:"steps"`
}

type HelpShortcut struct {
	Keys   string `json:"keys"`
	Scope  string `json:"scope"`
	Action string `json:"action"`
}

type HelpWhatsNewEntry struct {
	Version    string   `json:"version"`
	Date       string   `json:"date"`
	Channel    string   `json:"channel"`
	Highlights []string `json:"highlights"`
}

type HelpDataUseAgreement struct {
	Title     string   `json:"title"`
	Authority string   `json:"authority"`
	SourceURL string   `json:"sourceUrl"`
	Citation  string   `json:"citation"`
	Clauses   []string `json:"clauses"`
}

type HelpBundle struct {
	SchemaVersion    int                  `json:"schemaVersion"`
	ProductName      string               `json:"productName"`
	FullName         string               `json:"fullName"`
	Organization     string               `json:"organization"`
	LMH25Edition     string               `json:"lmh25Edition"`
	LibraryStamps    LibraryStamps        `json:"libraryStamps"`
	Fields           []HelpFieldTopic     `json:"fields"`
	DecisionKeys     []HelpDecisionKey    `json:"decisionKeys"`
	Guides           []HelpGuide          `json:"guides"`
	Tours            []HelpTour           `json:"tours"`
	Shortcuts        []HelpShortcut       `json:"shortcuts"`
	WhatsNew         []HelpWhatsNewEntry  `json:"whatsNew"`
	DataUseAgreement HelpDataUseAgreement `json:"dataUseAgreement"`
}

type HelpLookupResult struct {
	RequestedID   string           `json:"requestedId"`
	ResolvedID    string           `json:"resolvedId"`
	MatchKind     string           `json:"matchKind"`
	Field         *HelpFieldTopic  `json:"field,omitempty"`
	DecisionKey   *HelpDecisionKey `json:"decisionKey,omitempty"`
	RelatedGuides []HelpGuide      `json:"relatedGuides"`
}

type HelpSearchHit struct {
	Kind      string `json:"kind"`
	ID        string `json:"id"`
	Code      string `json:"code,omitempty"`
	Title     string `json:"title"`
	Section   string `json:"section,omitempty"`
	Snippet   string `json:"snippet"`
	LMH25Page int    `json:"lmh25Page,omitempty"`
	Score     int    `json:"score"`
}

type WhatsNewStatus struct {
	LatestVersion   string              `json:"latestVersion"`
	LastSeenVersion string              `json:"lastSeenVersion"`
	HasUnread       bool                `json:"hasUnread"`
	UnreadCount     int                 `json:"unreadCount"`
	Entries         []HelpWhatsNewEntry `json:"entries"`
}

func parseHelpBundle(data []byte, stamps LibraryStamps) (HelpBundle, error) {
	var raw struct {
		SchemaVersion    int                  `json:"schemaVersion"`
		ProductName      string               `json:"productName"`
		FullName         string               `json:"fullName"`
		Organization     string               `json:"organization"`
		LMH25Edition     string               `json:"lmh25Edition"`
		Provenance       json.RawMessage      `json:"provenance"`
		Fields           []HelpFieldTopic     `json:"fields"`
		DecisionKeys     []HelpDecisionKey    `json:"decisionKeys"`
		Guides           []HelpGuide          `json:"guides"`
		Tours            []HelpTour           `json:"tours"`
		Shortcuts        []HelpShortcut       `json:"shortcuts"`
		WhatsNew         []HelpWhatsNewEntry  `json:"whatsNew"`
		DataUseAgreement HelpDataUseAgreement `json:"dataUseAgreement"`
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&raw); err != nil {
		return HelpBundle{}, fmt.Errorf("decode help bundle: %w", err)
	}
	if raw.SchemaVersion != 1 ||
		raw.ProductName == "" ||
		len(raw.Fields) == 0 ||
		len(raw.DecisionKeys) == 0 ||
		len(raw.Guides) == 0 ||
		len(raw.Tours) < 4 ||
		len(raw.Shortcuts) == 0 ||
		len(raw.WhatsNew) == 0 ||
		len(raw.DataUseAgreement.Clauses) == 0 {
		return HelpBundle{}, errors.New("embedded help bundle is incomplete")
	}
	bundle := HelpBundle{
		SchemaVersion:    raw.SchemaVersion,
		ProductName:      raw.ProductName,
		FullName:         raw.FullName,
		Organization:     raw.Organization,
		LMH25Edition:     raw.LMH25Edition,
		LibraryStamps:    cloneLibraryStamps(stamps),
		Fields:           raw.Fields,
		DecisionKeys:     raw.DecisionKeys,
		Guides:           raw.Guides,
		Tours:            raw.Tours,
		Shortcuts:        raw.Shortcuts,
		WhatsNew:         raw.WhatsNew,
		DataUseAgreement: raw.DataUseAgreement,
	}
	return cloneHelpBundle(bundle), nil
}

func cloneHelpFieldTopic(src HelpFieldTopic) HelpFieldTopic {
	dst := src
	dst.Rules = make([]string, len(src.Rules))
	copy(dst.Rules, src.Rules)
	dst.Codes = make([]HelpCodeOption, len(src.Codes))
	copy(dst.Codes, src.Codes)
	return dst
}

func cloneHelpDecisionKey(src HelpDecisionKey) HelpDecisionKey {
	dst := src
	dst.Steps = make([]HelpDecisionStep, len(src.Steps))
	copy(dst.Steps, src.Steps)
	return dst
}

func cloneHelpGuide(src HelpGuide) HelpGuide {
	dst := src
	dst.Sections = make([]HelpGuideSection, len(src.Sections))
	copy(dst.Sections, src.Sections)
	return dst
}

func cloneHelpTour(src HelpTour) HelpTour {
	dst := src
	dst.Steps = make([]HelpTourStep, len(src.Steps))
	copy(dst.Steps, src.Steps)
	return dst
}

func cloneHelpWhatsNewEntry(src HelpWhatsNewEntry) HelpWhatsNewEntry {
	dst := src
	dst.Highlights = make([]string, len(src.Highlights))
	copy(dst.Highlights, src.Highlights)
	return dst
}

func cloneHelpDataUseAgreement(src HelpDataUseAgreement) HelpDataUseAgreement {
	dst := src
	dst.Clauses = make([]string, len(src.Clauses))
	copy(dst.Clauses, src.Clauses)
	return dst
}

func cloneHelpBundle(src HelpBundle) HelpBundle {
	dst := src
	dst.LibraryStamps = cloneLibraryStamps(src.LibraryStamps)
	dst.Fields = make([]HelpFieldTopic, len(src.Fields))
	for i, f := range src.Fields {
		dst.Fields[i] = cloneHelpFieldTopic(f)
	}
	dst.DecisionKeys = make([]HelpDecisionKey, len(src.DecisionKeys))
	for i, k := range src.DecisionKeys {
		dst.DecisionKeys[i] = cloneHelpDecisionKey(k)
	}
	dst.Guides = make([]HelpGuide, len(src.Guides))
	for i, g := range src.Guides {
		dst.Guides[i] = cloneHelpGuide(g)
	}
	dst.Tours = make([]HelpTour, len(src.Tours))
	for i, t := range src.Tours {
		dst.Tours[i] = cloneHelpTour(t)
	}
	dst.Shortcuts = make([]HelpShortcut, len(src.Shortcuts))
	copy(dst.Shortcuts, src.Shortcuts)
	dst.WhatsNew = make([]HelpWhatsNewEntry, len(src.WhatsNew))
	for i, w := range src.WhatsNew {
		dst.WhatsNew[i] = cloneHelpWhatsNewEntry(w)
	}
	dst.DataUseAgreement = cloneHelpDataUseAgreement(src.DataUseAgreement)
	return dst
}

func validateCleanText(input, label string) error {
	if !utf8.ValidString(input) || strings.ContainsRune(input, 0) {
		return fmt.Errorf("%s contains malformed UTF-8 or NUL characters", label)
	}
	return nil
}

func (s *HelpService) requireReady(ctx context.Context, op string) error {
	if ctx == nil {
		return fmt.Errorf("%s requires a context", op)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if s == nil {
		return errors.New("help service is unavailable")
	}
	return nil
}

func (s *HelpService) GetHelpBundle(ctx context.Context) (HelpBundle, error) {
	if err := s.requireReady(ctx, "help bundle lookup"); err != nil {
		return HelpBundle{}, err
	}
	return cloneHelpBundle(s.bundle), nil
}

func (s *HelpService) readLastSeenWhatsNewVersion() (string, error) {
	if s.preferences == nil {
		return "", nil
	}
	values, err := s.preferences.Snapshot()
	if err != nil {
		return "", err
	}
	if msgSection, ok := values["Message"].(map[string]any); ok {
		if raw, exists := msgSection[whatsNewConfigKey]; exists {
			if v, ok := raw.(string); ok {
				return strings.TrimSpace(v), nil
			}
		}
	}
	if raw, exists := values[whatsNewConfigKey]; exists {
		if v, ok := raw.(string); ok {
			return strings.TrimSpace(v), nil
		}
	}
	return "", nil
}

func (s *HelpService) GetWhatsNewStatus(ctx context.Context) (WhatsNewStatus, error) {
	if err := s.requireReady(ctx, "what's new lookup"); err != nil {
		return WhatsNewStatus{}, err
	}
	lastSeen, err := s.readLastSeenWhatsNewVersion()
	if err != nil {
		return WhatsNewStatus{}, err
	}
	entries := make([]HelpWhatsNewEntry, len(s.bundle.WhatsNew))
	for i, e := range s.bundle.WhatsNew {
		entries[i] = cloneHelpWhatsNewEntry(e)
	}
	latest := ""
	if len(entries) > 0 {
		latest = entries[0].Version
	}
	unreadCount := len(entries)
	if lastSeen != "" {
		for idx, e := range entries {
			if e.Version == lastSeen {
				unreadCount = idx
				break
			}
		}
	}
	return WhatsNewStatus{
		LatestVersion:   latest,
		LastSeenVersion: lastSeen,
		HasUnread:       unreadCount > 0,
		UnreadCount:     unreadCount,
		Entries:         entries,
	}, nil
}

func (s *HelpService) AcknowledgeWhatsNew(ctx context.Context, version string) (WhatsNewStatus, error) {
	if err := s.requireReady(ctx, "what's new acknowledgement"); err != nil {
		return WhatsNewStatus{}, err
	}
	if err := validateCleanText(version, "what's new version"); err != nil {
		return WhatsNewStatus{}, err
	}
	target := strings.TrimSpace(version)
	if target == "" {
		return WhatsNewStatus{}, errors.New("what's new version is required")
	}
	if strings.EqualFold(target, "latest") && len(s.bundle.WhatsNew) > 0 {
		target = s.bundle.WhatsNew[0].Version
	}
	known := false
	for _, entry := range s.bundle.WhatsNew {
		if entry.Version == target {
			known = true
			break
		}
	}
	if !known {
		return WhatsNewStatus{}, fmt.Errorf("unknown release notes version %q", target)
	}
	if s.preferences == nil {
		return WhatsNewStatus{}, errors.New("desktop configuration is unavailable")
	}
	if err := s.preferences.Update("Message", map[string]any{
		whatsNewConfigKey: target,
	}); err != nil {
		return WhatsNewStatus{}, err
	}
	return s.GetWhatsNewStatus(ctx)
}

func writePristineSampleFile(destination string) (resultErr error) {
	dir := filepath.Dir(destination)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".sample-pristine-*.db")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer func() {
		if tmp != nil {
			resultErr = errors.Join(resultErr, tmp.Close())
		}
		if removeErr := os.Remove(tmpName); !errors.Is(removeErr, os.ErrNotExist) {
			resultErr = errors.Join(resultErr, removeErr)
		}
	}()
	if err := tmp.Chmod(0600); err != nil {
		return err
	}
	if _, err := tmp.Write(resources.SampleDB); err != nil {
		return err
	}
	if err := tmp.Sync(); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		tmp = nil
		return err
	}
	tmp = nil

	for _, sidecar := range []string{destination + "-wal", destination + "-shm"} {
		if err := os.Remove(sidecar); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("clear SQLite WAL sidecar %s: %w", filepath.Base(sidecar), err)
		}
	}
	if err := os.Rename(tmpName, destination); err != nil {
		return fmt.Errorf("install pristine Sample database: %w", err)
	}
	return nil
}

func removeSampleStagingFiles(stagingPath string) {
	for _, p := range []string{stagingPath + "-wal", stagingPath + "-shm", stagingPath} {
		_ = os.Remove(p)
	}
	_ = os.Remove(filepath.Dir(stagingPath))
}

func (s *HelpService) ResetWorkspaceToSample(ctx context.Context, contextID string) (vprocore.ProjectState, error) {
	if err := s.requireReady(ctx, "workspace sample reset"); err != nil {
		return vprocore.ProjectState{}, err
	}
	if err := validateCleanText(contextID, "context ID"); err != nil {
		return vprocore.ProjectState{}, err
	}
	if strings.TrimSpace(contextID) == "" {
		return vprocore.ProjectState{}, errors.New("context ID is required before resetting workspace to Sample")
	}
	if s.contexts == nil || s.contexts.Projects == nil {
		return vprocore.ProjectState{}, errors.New("project context service is unavailable")
	}

	projects := s.contexts.Projects
	projectsDir := filepath.Join(projects.Root, "projects")
	samplePath, err := filepath.Abs(filepath.Join(projectsDir, "Sample.db"))
	if err != nil {
		return vprocore.ProjectState{}, err
	}

	projects.Mu.RLock()
	currentID := projects.ContextID
	sqliteCtx := projects.Sqlite
	profileUsesSample := false
	if sqliteCtx != nil && sqliteCtx.Profile != nil && vprocore.SameDesktopPath(sqliteCtx.Profile.Path, samplePath) {
		profileUsesSample = true
	}
	projects.Mu.RUnlock()

	if currentID == "" || contextID != currentID {
		return vprocore.ProjectState{}, errors.New("project context changed; reload before resetting workspace to Sample")
	}
	if err := ctx.Err(); err != nil {
		return vprocore.ProjectState{}, err
	}

	stagingDir, err := os.MkdirTemp(projects.Root, ".sample-reset-staging-*")
	if err != nil {
		return vprocore.ProjectState{}, err
	}
	cleanupStaging := true
	defer func() {
		if cleanupStaging {
			_ = os.RemoveAll(stagingDir)
		}
	}()
	stagingPath := filepath.Join(stagingDir, "Sample_Staging.db")
	if err := writePristineSampleFile(stagingPath); err != nil {
		return vprocore.ProjectState{}, err
	}

	activeID := contextID
	if profileUsesSample {
		profState, err := s.contexts.SelectPlotProfile(activeID, vprocore.PlotProfileSource{
			Name: "Sample",
			Path: stagingPath,
		})
		if err != nil {
			return vprocore.ProjectState{}, err
		}
		activeID = profState.ContextID
	}

	// Atomically verify activeID under projects.Mu.Lock and detach Sample.db before overwriting it.
	stagedState, err := s.contexts.SwitchContext(activeID, vprocore.ContextSelection{
		Project:       "Sample",
		ProjectPath:   stagingPath,
		SU:            "Sample",
		SUPath:        stagingPath,
		Hierarchy:     "Sample",
		HierarchyPath: stagingPath,
	})
	if err != nil {
		return vprocore.ProjectState{}, err
	}
	// Preserve stagingDir if final replacement/switch fails so the active staged context is never stranded.
	cleanupStaging = false

	if err := writePristineSampleFile(samplePath); err != nil {
		return vprocore.ProjectState{}, err
	}

	finalState, err := s.contexts.SwitchContext(stagedState.ContextID, vprocore.ContextSelection{
		Project:       "Sample",
		ProjectPath:   samplePath,
		SU:            "Sample",
		SUPath:        samplePath,
		Hierarchy:     "Sample",
		HierarchyPath: samplePath,
	})
	if err != nil {
		return vprocore.ProjectState{}, err
	}

	if profileUsesSample {
		finalState, err = s.contexts.SelectPlotProfile(finalState.ContextID, vprocore.PlotProfileSource{
			Name: "Sample",
			Path: samplePath,
		})
		if err != nil {
			return vprocore.ProjectState{}, err
		}
	}
	removeSampleStagingFiles(stagingPath)
	_ = os.RemoveAll(stagingDir)

	return finalState, nil
}
