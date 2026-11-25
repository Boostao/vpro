package main

import (
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
	ManifestSchemaVersion = 1
	ManifestFilename      = "manifest.json"
)

var snapshotIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)

// Manifest describes a published immutable read-only BECMaster/VPro snapshot bundle.
type Manifest struct {
	SchemaVersion     int                        `json:"schemaVersion"`
	SnapshotID        string                     `json:"snapshotId"`
	PublishedAt       string                     `json:"publishedAt"`
	Redacted          bool                       `json:"redacted"`
	RedactedPlotCount int                        `json:"redactedPlotCount"`
	Standards         StandardsStamp             `json:"standards"`
	SupportFiles      map[string]SupportFileSpec `json:"supportFiles"`
	AuxiliaryFiles    map[string]SupportFileSpec `json:"auxiliaryFiles,omitempty"`
	Datasets          []DatasetSpec              `json:"datasets"`
}

// StandardsStamp records the provincial BEC/taxonomy standards versions and VLists checksum.
type StandardsStamp struct {
	BECVersion          string         `json:"becVersion"`
	TaxonomyVersion     string         `json:"taxonomyVersion"`
	LMH25PDF2023SHA256  string         `json:"lmh25Pdf2023Sha256,omitempty"`
	VListsSHA256        string         `json:"vlistsSha256"`
	RedBlueSpeciesCount int            `json:"redBlueSpeciesCount"`
	TableCounts         map[string]int `json:"tableCounts,omitempty"`
}

// SupportFileSpec identifies one immutable support or auxiliary SQLite file inside the bundle.
type SupportFileSpec struct {
	File      string `json:"file"`
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes,omitempty"`
}

// DatasetSpec identifies one VP08 project dataset published inside the snapshot bundle.
type DatasetSpec struct {
	ID                string           `json:"id"`
	Label             string           `json:"label"`
	Project           string           `json:"project"`
	File              string           `json:"file"`
	SHA256            string           `json:"sha256"`
	SizeBytes         int64            `json:"sizeBytes,omitempty"`
	PlotCount         int              `json:"plotCount"`
	RedactedPlotCount int              `json:"redactedPlotCount"`
	SUs               []SUEntry        `json:"sus"`
	Hierarchies       []HierarchyEntry `json:"hierarchies"`
}

// SUEntry describes a compatible *_SU table inside a published dataset.
type SUEntry struct {
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	File       string `json:"file"`
	Compatible bool   `json:"compatible"`
}

// HierarchyEntry describes a compatible *_Hierarchy table inside the snapshot bundle.
type HierarchyEntry struct {
	Name       string `json:"name"`
	File       string `json:"file"`
	Version    string `json:"version"`
	Compatible bool   `json:"compatible"`
}

type embeddedStandardsProvenance struct {
	Sources []struct {
		ArchiveName string `json:"archiveName"`
		Version     string `json:"version"`
	} `json:"sources"`
	LMH25PDF2023SHA256 string `json:"lmh25Pdf2023Sha256"`
}

// LoadEmbeddedStandardsBase parses embedded standards-2026-provenance.json stamps.
func LoadEmbeddedStandardsBase() (becVersion, taxonomyVersion, lmh25SHA string) {
	becVersion = "BECdb_v13_2026"
	taxonomyVersion = "BCPlantTaxa_v19_2025"

	var prov embeddedStandardsProvenance
	if err := json.Unmarshal(resources.Standards2026ProvenanceJSON, &prov); err != nil {
		return becVersion, taxonomyVersion, lmh25SHA
	}
	lmh25SHA = strings.TrimSpace(prov.LMH25PDF2023SHA256)
	for _, src := range prov.Sources {
		lower := strings.ToLower(src.ArchiveName)
		ver := strings.TrimSpace(src.Version)
		if ver == "" {
			continue
		}
		if strings.Contains(lower, "becdb") {
			becVersion = ver
		} else if strings.Contains(lower, "planttaxa") || strings.Contains(lower, "taxonomy") {
			taxonomyVersion = ver
		}
	}
	return becVersion, taxonomyVersion, lmh25SHA
}

// ComputeFileSHA256 streams path and returns its lowercase hex SHA-256 digest and byte size.
func ComputeFileSHA256(filePath string) (string, int64, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", 0, err
	}
	defer f.Close()

	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(h.Sum(nil)), n, nil
}

// ValidateBundleRelPath validates that rel is a clean forward-slash relative path inside the bundle.
func ValidateBundleRelPath(rel string) error {
	trimmed := strings.TrimSpace(rel)
	if trimmed == "" {
		return errors.New("bundle relative path must not be empty")
	}
	if strings.Contains(trimmed, `\`) || strings.HasPrefix(trimmed, "/") {
		return fmt.Errorf("bundle path %q must be a clean forward-slash relative path", rel)
	}
	cleaned := path.Clean(trimmed)
	if cleaned != trimmed || cleaned == "." || cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return fmt.Errorf("bundle path %q escapes bundle root or is not normalized", rel)
	}
	return nil
}

// SafeBundleRelPath resolves rel inside bundleDir and verifies it does not escape bundleDir.
func SafeBundleRelPath(bundleDir, rel string) (string, error) {
	if err := ValidateBundleRelPath(rel); err != nil {
		return "", err
	}
	absBundle, err := filepath.Abs(bundleDir)
	if err != nil {
		return "", fmt.Errorf("resolve bundle directory: %w", err)
	}
	if resolvedBundle, err := filepath.EvalSymlinks(absBundle); err == nil {
		absBundle = resolvedBundle
	}
	candidate := filepath.Join(absBundle, filepath.FromSlash(rel))
	relCheck, err := filepath.Rel(absBundle, candidate)
	if err != nil || relCheck == ".." || strings.HasPrefix(relCheck, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("bundle path %q resolves outside bundle directory", rel)
	}
	if resolvedCand, err := filepath.EvalSymlinks(candidate); err == nil {
		relResolved, rErr := filepath.Rel(absBundle, resolvedCand)
		if rErr != nil || relResolved == ".." || strings.HasPrefix(relResolved, ".."+string(filepath.Separator)) {
			return "", fmt.Errorf("bundle path %q symlink escapes bundle directory", rel)
		}
	}
	return candidate, nil
}

func isValidSHA256Hex(s string) bool {
	if len(s) != 64 {
		return false
	}
	_, err := hex.DecodeString(s)
	return err == nil
}

// ValidateManifest checks structural, security, and schema invariants on m.
func ValidateManifest(m *Manifest) error {
	if m == nil {
		return errors.New("manifest is nil")
	}
	if m.SchemaVersion != ManifestSchemaVersion {
		return fmt.Errorf("unsupported manifest schemaVersion %d (expected %d)", m.SchemaVersion, ManifestSchemaVersion)
	}
	if !snapshotIDPattern.MatchString(m.SnapshotID) {
		return fmt.Errorf("invalid snapshotId %q", m.SnapshotID)
	}
	if _, err := time.Parse(time.RFC3339, m.PublishedAt); err != nil {
		return fmt.Errorf("invalid publishedAt %q: %w", m.PublishedAt, err)
	}
	if m.RedactedPlotCount < 0 {
		return fmt.Errorf("redactedPlotCount must be non-negative, got %d", m.RedactedPlotCount)
	}
	if !m.Redacted && m.RedactedPlotCount != 0 {
		return fmt.Errorf("unredacted manifest must have redactedPlotCount=0, got %d", m.RedactedPlotCount)
	}
	if len(m.SupportFiles) != len(vprocore.DatabaseFamilySeeds) {
		return fmt.Errorf("supportFiles must contain exactly %d VP08 support roles, got %d", len(vprocore.DatabaseFamilySeeds), len(m.SupportFiles))
	}
	for _, seed := range vprocore.DatabaseFamilySeeds {
		spec, ok := m.SupportFiles[seed.Name]
		if !ok {
			return fmt.Errorf("supportFiles is missing required VP08 role %q", seed.Name)
		}
		if err := ValidateBundleRelPath(spec.File); err != nil {
			return fmt.Errorf("supportFiles[%s].file: %w", seed.Name, err)
		}
		if !isValidSHA256Hex(spec.SHA256) {
			return fmt.Errorf("supportFiles[%s].sha256 is invalid: %q", seed.Name, spec.SHA256)
		}
	}
	if !isValidSHA256Hex(m.Standards.VListsSHA256) {
		return fmt.Errorf("standards.vlistsSha256 is invalid: %q", m.Standards.VListsSHA256)
	}
	if m.Standards.VListsSHA256 != m.SupportFiles["VLists"].SHA256 {
		return fmt.Errorf("standards.vlistsSha256 (%s) does not match supportFiles[VLists].sha256 (%s)",
			m.Standards.VListsSHA256, m.SupportFiles["VLists"].SHA256)
	}

	knownFiles := map[string]string{}
	for _, spec := range m.SupportFiles {
		knownFiles[spec.File] = spec.SHA256
	}
	for key, spec := range m.AuxiliaryFiles {
		if err := ValidateBundleRelPath(spec.File); err != nil {
			return fmt.Errorf("auxiliaryFiles[%s].file: %w", key, err)
		}
		if !isValidSHA256Hex(spec.SHA256) {
			return fmt.Errorf("auxiliaryFiles[%s].sha256 is invalid: %q", key, spec.SHA256)
		}
		knownFiles[spec.File] = spec.SHA256
	}

	if len(m.Datasets) == 0 {
		return errors.New("manifest must contain at least one dataset")
	}
	seenIDs := map[string]bool{}
	seenProjectInFile := map[string]bool{}
	sumRedacted := 0
	for i, ds := range m.Datasets {
		if strings.TrimSpace(ds.ID) == "" {
			return fmt.Errorf("datasets[%d].id must not be empty", i)
		}
		if seenIDs[ds.ID] {
			return fmt.Errorf("duplicate dataset id %q", ds.ID)
		}
		seenIDs[ds.ID] = true

		if strings.TrimSpace(ds.Label) == "" {
			return fmt.Errorf("datasets[%d].label must not be empty", i)
		}
		if !vprocore.ProjectNamePattern.MatchString(ds.Project) {
			return fmt.Errorf("datasets[%d].project %q is not a valid VP08 project name", i, ds.Project)
		}
		if err := ValidateBundleRelPath(ds.File); err != nil {
			return fmt.Errorf("datasets[%d].file: %w", i, err)
		}
		if !isValidSHA256Hex(ds.SHA256) {
			return fmt.Errorf("datasets[%d].sha256 is invalid: %q", i, ds.SHA256)
		}
		if prevHash, exists := knownFiles[ds.File]; exists && prevHash != ds.SHA256 {
			return fmt.Errorf("conflicting sha256 hashes recorded for file %q", ds.File)
		}
		knownFiles[ds.File] = ds.SHA256

		pfKey := ds.File + "::" + ds.Project
		if seenProjectInFile[pfKey] {
			return fmt.Errorf("duplicate dataset project %q in file %q", ds.Project, ds.File)
		}
		seenProjectInFile[pfKey] = true

		if ds.PlotCount < 0 {
			return fmt.Errorf("datasets[%d].plotCount must be non-negative, got %d", i, ds.PlotCount)
		}
		if ds.RedactedPlotCount < 0 {
			return fmt.Errorf("datasets[%d].redactedPlotCount must be non-negative, got %d", i, ds.RedactedPlotCount)
		}
		if !m.Redacted && ds.RedactedPlotCount != 0 {
			return fmt.Errorf("unredacted dataset %q must have redactedPlotCount=0, got %d", ds.ID, ds.RedactedPlotCount)
		}
		sumRedacted += ds.RedactedPlotCount

		for j, su := range ds.SUs {
			if !vprocore.ProjectNamePattern.MatchString(su.Name) {
				return fmt.Errorf("datasets[%d].sus[%d].name %q is invalid", i, j, su.Name)
			}
			if err := ValidateBundleRelPath(su.File); err != nil {
				return fmt.Errorf("datasets[%d].sus[%d].file: %w", i, j, err)
			}
		}
		for j, h := range ds.Hierarchies {
			if !vprocore.ProjectNamePattern.MatchString(h.Name) {
				return fmt.Errorf("datasets[%d].hierarchies[%d].name %q is invalid", i, j, h.Name)
			}
			if err := ValidateBundleRelPath(h.File); err != nil {
				return fmt.Errorf("datasets[%d].hierarchies[%d].file: %w", i, j, err)
			}
		}
	}
	if sumRedacted != m.RedactedPlotCount {
		return fmt.Errorf("manifest redactedPlotCount (%d) does not equal sum of dataset redactedPlotCount (%d)",
			m.RedactedPlotCount, sumRedacted)
	}
	for _, ds := range m.Datasets {
		for _, su := range ds.SUs {
			if _, ok := knownFiles[su.File]; !ok {
				return fmt.Errorf("dataset %q SU %q references unhashed file %q", ds.ID, su.Name, su.File)
			}
		}
		for _, h := range ds.Hierarchies {
			if _, ok := knownFiles[h.File]; !ok {
				return fmt.Errorf("dataset %q hierarchy %q references unhashed file %q", ds.ID, h.Name, h.File)
			}
		}
	}
	return nil
}

// ReadManifest loads and strictly validates manifest.json.
func ReadManifest(manifestPath string) (*Manifest, error) {
	raw, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, err
	}
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.DisallowUnknownFields()
	var m Manifest
	if err := dec.Decode(&m); err != nil {
		return nil, fmt.Errorf("decode %s: %w", manifestPath, err)
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("decode %s: unexpected trailing JSON data", manifestPath)
	}
	if err := ValidateManifest(&m); err != nil {
		return nil, fmt.Errorf("validate %s: %w", manifestPath, err)
	}
	return &m, nil
}

// WriteManifest validates and writes m to manifestPath with deterministic JSON formatting.
func WriteManifest(manifestPath string, m *Manifest) error {
	if err := ValidateManifest(m); err != nil {
		return err
	}
	// Ensure deterministic slice ordering for stable manifests.
	for i := range m.Datasets {
		if m.Datasets[i].SUs == nil {
			m.Datasets[i].SUs = []SUEntry{}
		}
		if m.Datasets[i].Hierarchies == nil {
			m.Datasets[i].Hierarchies = []HierarchyEntry{}
		}
		slices.SortFunc(m.Datasets[i].SUs, func(a, b SUEntry) int {
			if c := strings.Compare(a.Name, b.Name); c != 0 {
				return c
			}
			return strings.Compare(a.File, b.File)
		})
		slices.SortFunc(m.Datasets[i].Hierarchies, func(a, b HierarchyEntry) int {
			if c := strings.Compare(a.Name, b.Name); c != 0 {
				return c
			}
			return strings.Compare(a.File, b.File)
		})
	}
	encoded, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	return os.WriteFile(manifestPath, encoded, 0o644)
}
