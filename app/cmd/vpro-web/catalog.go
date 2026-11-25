package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
)

const (
	snapshotManifestSchemaVersion = 1
	snapshotManifestFilename      = "manifest.json"
)

var webSnapshotIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)

// SnapshotManifest matches the manifest.json schema emitted by cmd/vpro-snapshot.
type SnapshotManifest struct {
	SchemaVersion     int                        `json:"schemaVersion"`
	SnapshotID        string                     `json:"snapshotId"`
	PublishedAt       string                     `json:"publishedAt"`
	Redacted          bool                       `json:"redacted"`
	RedactedPlotCount int                        `json:"redactedPlotCount"`
	Standards         SnapshotStandardsStamp     `json:"standards"`
	SupportFiles      map[string]SnapshotFileRef `json:"supportFiles"`
	AuxiliaryFiles    map[string]SnapshotFileRef `json:"auxiliaryFiles,omitempty"`
	Datasets          []SnapshotDatasetSpec      `json:"datasets"`
}

type SnapshotStandardsStamp struct {
	BECVersion          string         `json:"becVersion"`
	TaxonomyVersion     string         `json:"taxonomyVersion"`
	LMH25PDF2023SHA256  string         `json:"lmh25Pdf2023Sha256,omitempty"`
	VListsSHA256        string         `json:"vlistsSha256"`
	RedBlueSpeciesCount int            `json:"redBlueSpeciesCount"`
	TableCounts         map[string]int `json:"tableCounts,omitempty"`
}

type SnapshotFileRef struct {
	File      string `json:"file"`
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes,omitempty"`
}

type SnapshotDatasetSpec struct {
	ID                string                  `json:"id"`
	Label             string                  `json:"label"`
	Project           string                  `json:"project"`
	File              string                  `json:"file"`
	SHA256            string                  `json:"sha256"`
	SizeBytes         int64                   `json:"sizeBytes,omitempty"`
	PlotCount         int                     `json:"plotCount"`
	RedactedPlotCount int                     `json:"redactedPlotCount"`
	SUs               []SnapshotSUEntry       `json:"sus"`
	Hierarchies       []SnapshotHierarchySpec `json:"hierarchies"`
}

type SnapshotSUEntry struct {
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	File       string `json:"file"`
	Compatible bool   `json:"compatible"`
}

type SnapshotHierarchySpec struct {
	Name       string `json:"name"`
	File       string `json:"file"`
	Version    string `json:"version"`
	Compatible bool   `json:"compatible"`
}

// LoadedSnapshot pairs the verified manifest metadata with the resolved vprocore.SnapshotCatalog.
type LoadedSnapshot struct {
	ResolvedRoot string
	Manifest     SnapshotManifest
	Catalog      vprocore.SnapshotCatalog
	// AllowedDBPaths lists every canonical database path owned by this snapshot bundle
	// (projects, SUs, hierarchies, support files) so RPC path guards can verify ownership.
	AllowedDBPaths map[string]bool
}

func (s *LoadedSnapshot) DefaultSelection() vprocore.SelectionKey {
	if s == nil || len(s.Catalog.Datasets) == 0 {
		return vprocore.SelectionKey{}
	}
	ds := s.Catalog.Datasets[0]
	su := ds.DefaultSU
	if su == "" {
		su = "None"
	}
	hier := ds.DefaultHierarchy
	if hier == "" {
		hier = "None"
	}
	return vprocore.SelectionKey{
		DatasetID: ds.ID,
		SU:        su,
		Hierarchy: hier,
	}
}

func (s *LoadedSnapshot) FindDataset(idOrProject, optionalPath string) (vprocore.SnapshotDataset, bool) {
	if s == nil {
		return vprocore.SnapshotDataset{}, false
	}
	trimmed := strings.TrimSpace(idOrProject)
	trimmedPath := strings.TrimSpace(optionalPath)

	// 1. Exact ID match (and optional path check if provided).
	for _, ds := range s.Catalog.Datasets {
		if ds.ID == trimmed {
			if trimmedPath == "" || matchesDatasetPath(ds, trimmedPath) {
				return ds, true
			}
		}
	}
	// 2. Match by project name + optional path disambiguation.
	var firstMatch *vprocore.SnapshotDataset
	for i := range s.Catalog.Datasets {
		ds := &s.Catalog.Datasets[i]
		if ds.Project == trimmed {
			if trimmedPath != "" && matchesDatasetPath(*ds, trimmedPath) {
				return *ds, true
			}
			if firstMatch == nil {
				firstMatch = ds
			}
		}
	}
	if firstMatch != nil && trimmedPath == "" {
		return *firstMatch, true
	}
	return vprocore.SnapshotDataset{}, false
}

func matchesDatasetPath(ds vprocore.SnapshotDataset, candidate string) bool {
	if candidate == "" {
		return true
	}
	if candidate == ds.ProjectPath || candidate == ds.ID || candidate == filepath.Base(ds.ProjectPath) {
		return true
	}
	return vprocore.SameDesktopPath(ds.ProjectPath, candidate)
}

func (s *LoadedSnapshot) IsAllowedDBPath(candidate string) bool {
	if s == nil {
		return false
	}
	trimmed := strings.TrimSpace(candidate)
	if trimmed == "" {
		return true
	}
	if s.AllowedDBPaths[trimmed] {
		return true
	}
	abs, err := filepath.Abs(trimmed)
	if err == nil {
		if s.AllowedDBPaths[abs] {
			return true
		}
		if resolved, rErr := filepath.EvalSymlinks(abs); rErr == nil && s.AllowedDBPaths[resolved] {
			return true
		}
	}
	for owned := range s.AllowedDBPaths {
		if vprocore.SameDesktopPath(owned, trimmed) {
			return true
		}
	}
	return false
}

// LoadVerifiedSnapshot reads manifest.json from dataDir (resolving symlinks so atomic
// current -> releases/<id> flips reload cleanly), verifies every file's SHA-256 checksum
// and path containment, and constructs a vprocore.SnapshotCatalog with Immutable=true.
func LoadVerifiedSnapshot(dataDir string) (*LoadedSnapshot, error) {
	if strings.TrimSpace(dataDir) == "" {
		return nil, errors.New("snapshot data directory is empty")
	}
	absDir, err := filepath.Abs(dataDir)
	if err != nil {
		return nil, fmt.Errorf("resolve snapshot data dir: %w", err)
	}
	resolvedDir, err := filepath.EvalSymlinks(absDir)
	if err != nil {
		return nil, fmt.Errorf("eval symlinks for snapshot data dir %q: %w", dataDir, err)
	}
	info, err := os.Stat(resolvedDir)
	if err != nil {
		return nil, fmt.Errorf("stat snapshot data dir %q: %w", resolvedDir, err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("snapshot data path %q is not a directory", resolvedDir)
	}

	manifestPath := filepath.Join(resolvedDir, snapshotManifestFilename)
	raw, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", manifestPath, err)
	}
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.DisallowUnknownFields()
	var m SnapshotManifest
	if err := dec.Decode(&m); err != nil {
		return nil, fmt.Errorf("decode %s: %w", manifestPath, err)
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("decode %s: unexpected trailing JSON data", manifestPath)
	}
	if err := validateSnapshotManifest(&m); err != nil {
		return nil, fmt.Errorf("validate %s: %w", manifestPath, err)
	}

	verifiedPaths := map[string]string{} // rel -> abs resolved path
	allowedDBPaths := map[string]bool{}

	verifyFile := func(rel, expectedSHA string) (string, error) {
		if existing, ok := verifiedPaths[rel]; ok {
			return existing, nil
		}
		absPath, err := safeSnapshotRelPath(resolvedDir, rel)
		if err != nil {
			return "", err
		}
		actualSHA, err := computeFileSHA256Hex(absPath)
		if err != nil {
			return "", fmt.Errorf("hash %s: %w", rel, err)
		}
		if !strings.EqualFold(actualSHA, expectedSHA) {
			return "", fmt.Errorf("sha256 mismatch for %s: expected %s, got %s", rel, expectedSHA, actualSHA)
		}
		// Reject stray WAL/SHM sidecars in immutable snapshot bundles.
		for _, suffix := range []string{"-wal", "-shm"} {
			if _, statErr := os.Stat(absPath + suffix); statErr == nil {
				return "", fmt.Errorf("stray SQLite sidecar %s%s found in immutable snapshot bundle", rel, suffix)
			}
		}
		verifiedPaths[rel] = absPath
		allowedDBPaths[absPath] = true
		return absPath, nil
	}

	supportPaths := make(map[string]string, len(m.SupportFiles))
	for _, seed := range vprocore.DatabaseFamilySeeds {
		ref := m.SupportFiles[seed.Name]
		absPath, err := verifyFile(ref.File, ref.SHA256)
		if err != nil {
			return nil, fmt.Errorf("supportFiles[%s]: %w", seed.Name, err)
		}
		supportPaths[seed.Name] = absPath
	}
	for key, ref := range m.AuxiliaryFiles {
		if _, err := verifyFile(ref.File, ref.SHA256); err != nil {
			return nil, fmt.Errorf("auxiliaryFiles[%s]: %w", key, err)
		}
	}

	datasets := make([]vprocore.SnapshotDataset, 0, len(m.Datasets))
	for _, ds := range m.Datasets {
		projectAbs, err := verifyFile(ds.File, ds.SHA256)
		if err != nil {
			return nil, fmt.Errorf("dataset %q: %w", ds.ID, err)
		}
		suPaths := make(map[string]string, len(ds.SUs))
		suInfos := make([]vprocore.SUInfo, 0, len(ds.SUs))
		for _, su := range ds.SUs {
			suAbs, ok := verifiedPaths[su.File]
			if !ok {
				return nil, fmt.Errorf("dataset %q SU %q references unverified file %q", ds.ID, su.Name, su.File)
			}
			suPaths[su.Name] = suAbs
			suInfos = append(suInfos, vprocore.SUInfo{
				Name:       su.Name,
				Kind:       su.Kind,
				Compatible: su.Compatible,
				Path:       suAbs,
			})
		}

		hierPaths := make(map[string]string, len(ds.Hierarchies))
		hierInfos := make([]vprocore.HierarchyInfo, 0, len(ds.Hierarchies))
		defaultHier := "None"
		for _, h := range ds.Hierarchies {
			hAbs, ok := verifiedPaths[h.File]
			if !ok {
				return nil, fmt.Errorf("dataset %q hierarchy %q references unverified file %q", ds.ID, h.Name, h.File)
			}
			hierPaths[h.Name] = hAbs
			hierInfos = append(hierInfos, vprocore.HierarchyInfo{
				Name:       h.Name,
				File:       filepath.Base(hAbs),
				Path:       hAbs,
				Compatible: h.Compatible,
				Version:    h.Version,
			})
			if h.Compatible && defaultHier == "None" {
				if h.Name == ds.Project {
					defaultHier = h.Name
				}
			}
		}
		if defaultHier == "None" {
			for _, h := range hierInfos {
				if h.Compatible {
					defaultHier = h.Name
					break
				}
			}
		}

		datasets = append(datasets, vprocore.SnapshotDataset{
			ID:               ds.ID,
			Label:            ds.Label,
			Project:          ds.Project,
			ProjectPath:      projectAbs,
			SUPaths:          suPaths,
			HierarchyPaths:   hierPaths,
			DefaultSU:        "None",
			DefaultHierarchy: defaultHier,
			PlotCount:        ds.PlotCount,
			SUs:              suInfos,
			Hierarchies:      hierInfos,
		})
	}

	catalog := vprocore.SnapshotCatalog{
		Generation:   m.SnapshotID,
		SnapshotID:   m.SnapshotID,
		PublishedAt:  m.PublishedAt,
		Redacted:     m.Redacted,
		RootDir:      resolvedDir,
		SupportPaths: supportPaths,
		Datasets:     datasets,
		Immutable:    true,
	}

	return &LoadedSnapshot{
		ResolvedRoot:   resolvedDir,
		Manifest:       m,
		Catalog:        catalog,
		AllowedDBPaths: allowedDBPaths,
	}, nil
}

// ProvisionDevSampleSnapshot materializes an isolated read-only Sample.db workspace
// inside <exportDir>/dev-sample so local development works with --dev-sample without
// first running vpro-snapshot.
func ProvisionDevSampleSnapshot(ctx context.Context, exportDir string) (*LoadedSnapshot, error) {
	sampleRoot := filepath.Join(exportDir, "dev-sample")
	familyDir := filepath.Join(sampleRoot, "database-family")
	projectsDir := filepath.Join(sampleRoot, "projects")
	if err := os.MkdirAll(familyDir, 0o750); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(projectsDir, 0o750); err != nil {
		return nil, err
	}

	supportPaths := make(map[string]string, len(vprocore.DatabaseFamilySeeds))
	supportRefs := make(map[string]SnapshotFileRef, len(vprocore.DatabaseFamilySeeds))
	allowedDBPaths := map[string]bool{}

	for _, seed := range vprocore.DatabaseFamilySeeds {
		fileName := seed.Name + ".db"
		data, err := resources.DatabaseFamilyFS.ReadFile("database-family/" + fileName)
		if err != nil {
			return nil, fmt.Errorf("read embedded %s: %w", fileName, err)
		}
		target := filepath.Join(familyDir, fileName)
		if err := os.WriteFile(target, data, 0o444); err != nil {
			// If file already exists as 0444 from a previous dev run, replace cleanly.
			_ = os.Chmod(target, 0o644)
			if err := os.WriteFile(target, data, 0o444); err != nil {
				return nil, fmt.Errorf("write dev-sample %s: %w", fileName, err)
			}
		}
		sha, err := computeFileSHA256Hex(target)
		if err != nil {
			return nil, err
		}
		supportPaths[seed.Name] = target
		allowedDBPaths[target] = true
		supportRefs[seed.Name] = SnapshotFileRef{
			File:      "database-family/" + fileName,
			SHA256:    sha,
			SizeBytes: int64(len(data)),
		}
	}

	samplePath := filepath.Join(projectsDir, "Sample.db")
	if err := os.WriteFile(samplePath, resources.SampleDB, 0o444); err != nil {
		_ = os.Chmod(samplePath, 0o644)
		if err := os.WriteFile(samplePath, resources.SampleDB, 0o444); err != nil {
			return nil, fmt.Errorf("write dev-sample Sample.db: %w", err)
		}
	}
	sampleSHA, err := computeFileSHA256Hex(samplePath)
	if err != nil {
		return nil, err
	}
	allowedDBPaths[samplePath] = true

	sus, err := vprocore.DiscoverSUsReadOnly(ctx, samplePath, true)
	if err != nil {
		return nil, fmt.Errorf("discover dev-sample SUs: %w", err)
	}
	hierarchies, err := vprocore.DiscoverHierarchiesReadOnly(ctx, samplePath, true)
	if err != nil {
		return nil, fmt.Errorf("discover dev-sample hierarchies: %w", err)
	}
	plotCount, err := countProjectPlotsReadOnly(ctx, samplePath, "Sample")
	if err != nil {
		return nil, err
	}

	suPaths := map[string]string{}
	suEntries := make([]SnapshotSUEntry, 0, len(sus))
	for _, su := range sus {
		if !su.Compatible {
			continue
		}
		suPaths[su.Name] = samplePath
		suEntries = append(suEntries, SnapshotSUEntry{
			Name:       su.Name,
			Kind:       su.Kind,
			File:       "projects/Sample.db",
			Compatible: true,
		})
	}
	hierPaths := map[string]string{}
	hierEntries := make([]SnapshotHierarchySpec, 0, len(hierarchies))
	defaultHier := "None"
	for _, h := range hierarchies {
		if !h.Compatible {
			continue
		}
		hierPaths[h.Name] = samplePath
		hierEntries = append(hierEntries, SnapshotHierarchySpec{
			Name:       h.Name,
			File:       "projects/Sample.db",
			Version:    h.Version,
			Compatible: true,
		})
		if defaultHier == "None" || h.Name == "Sample" {
			defaultHier = h.Name
		}
	}

	now := time.Now().UTC().Format(time.RFC3339)
	manifest := SnapshotManifest{
		SchemaVersion:     snapshotManifestSchemaVersion,
		SnapshotID:        "dev-sample",
		PublishedAt:       now,
		Redacted:          false,
		RedactedPlotCount: 0,
		Standards: SnapshotStandardsStamp{
			BECVersion:      "BECdb_v13_2026",
			TaxonomyVersion: "BCPlantTaxa_v19_2025",
			VListsSHA256:    supportRefs["VLists"].SHA256,
		},
		SupportFiles: supportRefs,
		Datasets: []SnapshotDatasetSpec{
			{
				ID:          "sample",
				Label:       "Sample",
				Project:     "Sample",
				File:        "projects/Sample.db",
				SHA256:      sampleSHA,
				SizeBytes:   int64(len(resources.SampleDB)),
				PlotCount:   plotCount,
				SUs:         suEntries,
				Hierarchies: hierEntries,
			},
		},
	}

	catalog := vprocore.SnapshotCatalog{
		Generation:   "dev-sample",
		SnapshotID:   "dev-sample",
		PublishedAt:  now,
		Redacted:     false,
		RootDir:      sampleRoot,
		SupportPaths: supportPaths,
		Datasets: []vprocore.SnapshotDataset{
			{
				ID:               "sample",
				Label:            "Sample",
				Project:          "Sample",
				ProjectPath:      samplePath,
				SUPaths:          suPaths,
				HierarchyPaths:   hierPaths,
				DefaultSU:        "None",
				DefaultHierarchy: defaultHier,
				PlotCount:        plotCount,
				SUs:              sus,
				Hierarchies:      hierarchies,
			},
		},
		Immutable: true,
	}

	return &LoadedSnapshot{
		ResolvedRoot:   sampleRoot,
		Manifest:       manifest,
		Catalog:        catalog,
		AllowedDBPaths: allowedDBPaths,
	}, nil
}

func countProjectPlotsReadOnly(ctx context.Context, dbPath, project string) (int, error) {
	db, err := vprocore.OpenReadOnlySQLite(ctx, dbPath, true)
	if err != nil {
		return 0, err
	}
	defer db.Close()
	var n int
	query := "SELECT COUNT(*) FROM " + vprocore.QuoteHeaderIdentifier(project+"_Env")
	if err := db.QueryRowContext(ctx, query).Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}

func validateSnapshotManifest(m *SnapshotManifest) error {
	if m == nil {
		return errors.New("manifest is nil")
	}
	if m.SchemaVersion != snapshotManifestSchemaVersion {
		return fmt.Errorf("unsupported schemaVersion %d (expected %d)", m.SchemaVersion, snapshotManifestSchemaVersion)
	}
	if !webSnapshotIDPattern.MatchString(m.SnapshotID) {
		return fmt.Errorf("invalid snapshotId %q", m.SnapshotID)
	}
	if _, err := time.Parse(time.RFC3339, m.PublishedAt); err != nil {
		return fmt.Errorf("invalid publishedAt %q: %w", m.PublishedAt, err)
	}
	if m.RedactedPlotCount < 0 {
		return fmt.Errorf("redactedPlotCount must be non-negative")
	}
	if len(m.SupportFiles) != len(vprocore.DatabaseFamilySeeds) {
		return fmt.Errorf("supportFiles must contain %d VP08 roles, got %d", len(vprocore.DatabaseFamilySeeds), len(m.SupportFiles))
	}
	for _, seed := range vprocore.DatabaseFamilySeeds {
		spec, ok := m.SupportFiles[seed.Name]
		if !ok {
			return fmt.Errorf("supportFiles missing required role %q", seed.Name)
		}
		if err := validateBundleRelPath(spec.File); err != nil {
			return fmt.Errorf("supportFiles[%s].file: %w", seed.Name, err)
		}
		if !isValidSHA256HexString(spec.SHA256) {
			return fmt.Errorf("supportFiles[%s].sha256 is invalid", seed.Name)
		}
	}
	if !strings.EqualFold(m.Standards.VListsSHA256, m.SupportFiles["VLists"].SHA256) {
		return errors.New("standards.vlistsSha256 does not match supportFiles[VLists].sha256")
	}
	for key, spec := range m.AuxiliaryFiles {
		if err := validateBundleRelPath(spec.File); err != nil {
			return fmt.Errorf("auxiliaryFiles[%s].file: %w", key, err)
		}
		if !isValidSHA256HexString(spec.SHA256) {
			return fmt.Errorf("auxiliaryFiles[%s].sha256 is invalid", key)
		}
	}
	if len(m.Datasets) == 0 {
		return errors.New("manifest must contain at least one dataset")
	}
	seenIDs := map[string]bool{}
	for i, ds := range m.Datasets {
		if strings.TrimSpace(ds.ID) == "" {
			return fmt.Errorf("datasets[%d].id is empty", i)
		}
		if seenIDs[ds.ID] {
			return fmt.Errorf("duplicate dataset id %q", ds.ID)
		}
		seenIDs[ds.ID] = true
		if !vprocore.ProjectNamePattern.MatchString(ds.Project) {
			return fmt.Errorf("datasets[%d].project %q is invalid", i, ds.Project)
		}
		if err := validateBundleRelPath(ds.File); err != nil {
			return fmt.Errorf("datasets[%d].file: %w", i, err)
		}
		if !isValidSHA256HexString(ds.SHA256) {
			return fmt.Errorf("datasets[%d].sha256 is invalid", i)
		}
		for _, su := range ds.SUs {
			if !vprocore.ProjectNamePattern.MatchString(su.Name) {
				return fmt.Errorf("dataset %q SU %q has invalid name", ds.ID, su.Name)
			}
			if err := validateBundleRelPath(su.File); err != nil {
				return fmt.Errorf("dataset %q SU %q file: %w", ds.ID, su.Name, err)
			}
		}
		for _, h := range ds.Hierarchies {
			if !vprocore.ProjectNamePattern.MatchString(h.Name) {
				return fmt.Errorf("dataset %q hierarchy %q has invalid name", ds.ID, h.Name)
			}
			if err := validateBundleRelPath(h.File); err != nil {
				return fmt.Errorf("dataset %q hierarchy %q file: %w", ds.ID, h.Name, err)
			}
		}
	}
	return nil
}

func validateBundleRelPath(rel string) error {
	trimmed := strings.TrimSpace(rel)
	if trimmed == "" {
		return errors.New("path must not be empty")
	}
	if strings.Contains(trimmed, `\`) || strings.HasPrefix(trimmed, "/") {
		return fmt.Errorf("path %q must be a clean forward-slash relative path", rel)
	}
	cleaned := path.Clean(trimmed)
	if cleaned != trimmed || cleaned == "." || cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return fmt.Errorf("path %q escapes bundle root or is not normalized", rel)
	}
	return nil
}

func safeSnapshotRelPath(resolvedRoot, rel string) (string, error) {
	if err := validateBundleRelPath(rel); err != nil {
		return "", err
	}
	candidate := filepath.Join(resolvedRoot, filepath.FromSlash(rel))
	relCheck, err := filepath.Rel(resolvedRoot, candidate)
	if err != nil || relCheck == ".." || strings.HasPrefix(relCheck, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path %q resolves outside snapshot root", rel)
	}
	resolvedCand, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		return "", fmt.Errorf("resolve snapshot file %q: %w", rel, err)
	}
	relResolved, err := filepath.Rel(resolvedRoot, resolvedCand)
	if err != nil || relResolved == ".." || strings.HasPrefix(relResolved, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path %q symlink escapes snapshot root", rel)
	}
	info, err := os.Stat(resolvedCand)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() {
		return "", fmt.Errorf("snapshot file %q is not a regular file", rel)
	}
	return resolvedCand, nil
}

func computeFileSHA256Hex(filePath string) (string, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func isValidSHA256HexString(s string) bool {
	if len(s) != 64 {
		return false
	}
	_, err := hex.DecodeString(s)
	return err == nil
}

// buildWebProjectState builds a canonical vprocore.ProjectState for (ds, su, hierarchy)
// populated from the active LoadedSnapshot without performing any disk writes.
func buildWebProjectState(snap *LoadedSnapshot, ds vprocore.SnapshotDataset, su, hierarchy string) vprocore.ProjectState {
	if su == "" {
		su = "None"
	}
	if hierarchy == "" {
		hierarchy = "None"
	}
	projects := make([]vprocore.ProjectInfo, 0, len(snap.Catalog.Datasets))
	for _, d := range snap.Catalog.Datasets {
		projects = append(projects, vprocore.ProjectInfo{
			Name:       d.Project,
			File:       filepath.Base(d.ProjectPath),
			Path:       d.ProjectPath,
			Compatible: true,
			Version:    "VP08",
		})
	}
	sus := append([]vprocore.SUInfo(nil), ds.SUs...)
	if sus == nil {
		sus = []vprocore.SUInfo{}
	}
	hierarchies := append([]vprocore.HierarchyInfo(nil), ds.Hierarchies...)
	if hierarchies == nil {
		hierarchies = []vprocore.HierarchyInfo{}
	}

	suPath := ""
	if su != "None" {
		suPath = ds.SUPaths[su]
		if suPath == "" {
			suPath = ds.ProjectPath
		}
	}
	hierPath := ""
	hierFile := ""
	if hierarchy != "None" {
		hierPath = ds.HierarchyPaths[hierarchy]
		if hierPath == "" {
			hierPath = ds.ProjectPath
		}
		hierFile = filepath.Base(hierPath)
	}

	return vprocore.ProjectState{
		ActiveProject:   ds.Project,
		ActiveSU:        su,
		ActiveHierarchy: hierarchy,
		HierarchyFile:   hierFile,
		Projects:        projects,
		SUs:             sus,
		Hierarchies:     hierarchies,
		Diagnostics:     []vprocore.ProjectDiagnostic{},
		ContextID:       vprocore.EncodeWebContextID(snap.Catalog.Generation, ds.ID, su, hierarchy),
		ProjectPath:     ds.ProjectPath,
		SUPath:          suPath,
		HierarchyPath:   hierPath,
		PlotProfile: vprocore.PlotProfileSourceInfo{
			Source: vprocore.PlotProfileSource{
				Name: ds.Project,
				Path: ds.ProjectPath,
			},
			Table:     ds.Project + "_Profile",
			Available: true,
			Writable:  false,
		},
	}
}

func datasetHasCompatibleSU(ds vprocore.SnapshotDataset, su string) bool {
	if su == "" || su == "None" {
		return true
	}
	if _, ok := ds.SUPaths[su]; ok {
		return true
	}
	return slices.ContainsFunc(ds.SUs, func(item vprocore.SUInfo) bool {
		return item.Name == su && item.Compatible
	})
}

func datasetHasCompatibleHierarchy(ds vprocore.SnapshotDataset, h string) bool {
	if h == "" || h == "None" {
		return true
	}
	if _, ok := ds.HierarchyPaths[h]; ok {
		return true
	}
	return slices.ContainsFunc(ds.Hierarchies, func(item vprocore.HierarchyInfo) bool {
		return item.Name == h && item.Compatible
	})
}
