package main

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	_ "github.com/mattn/go-sqlite3"
)

// BuildOptions configures snapshot bundle creation via BuildSnapshot.
type BuildOptions struct {
	Source            string
	Out               string
	VLists            string
	SupportDir        string
	SnapshotID        string
	Label             string
	Redact            bool
	ConfirmUnredacted bool
	Force             bool
}

// VerifyResult summarizes a successful VerifyBundle run.
type VerifyResult struct {
	SnapshotID        string   `json:"snapshotId"`
	DatasetCount      int      `json:"datasetCount"`
	SupportFileCount  int      `json:"supportFileCount"`
	Redacted          bool     `json:"redacted"`
	RedactedPlotCount int      `json:"redactedPlotCount"`
	VerifiedFiles     []string `json:"verifiedFiles"`
	VerifiedDatasets  []string `json:"verifiedDatasets"`
}

var requiredSupportTables = map[string][]string{
	"VPro64": {"USysEnvTable", "USysVegTable", "USysSuTable", "USysHierarchyTable"},
	"VLists": {
		"USysAllSpecs", "USysTableOfLists", "MasterSiteUnitList", "USysMetadataTemplates",
		"USysZoneList", "USysMasterAudit", "USysSiteSeriesNames", "USysSppAttributes",
		"USysSppAttributeFieldList", "USysSppAttributeDescription",
	},
	"VUser":         {"USysUserSpp", "UserSiteUnitList", "USysSiteUnitAll", "USysPrefs"},
	"VMetaData":     {"ProjectMetadata", "ProjectMetaDataCodes"},
	"VMessageBoard": {"tblMessageBoard", "tblMessageList"},
}

var canonicalSupportFileNames = map[string]bool{
	"vpro64.db":        true,
	"vlists.db":        true,
	"vuser.db":         true,
	"vmetadata.db":     true,
	"vmessageboard.db": true,
	"vpics.db":         true,
}

var sqliteHeaderMagic = []byte("SQLite format 3\x00")

var requiredVegColumns = []string{
	"ID", "PlotNumber", "Species",
	"Cover1", "Cover2", "Cover3", "TotalA", "HeightA",
	"Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB", "HeightB",
	"Cover6", "Height6", "Cover7", "Cover8", "Cover9", "Collected",
}

// BuildSnapshot builds an immutable read-only BECMaster/VPro snapshot bundle without mutating source files.
func BuildSnapshot(ctx context.Context, opts BuildOptions) (*Manifest, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if strings.TrimSpace(opts.Source) == "" {
		return nil, errors.New("--source is required")
	}
	if strings.TrimSpace(opts.Out) == "" {
		return nil, errors.New("--out is required")
	}
	if !opts.Redact && !opts.ConfirmUnredacted {
		return nil, errors.New("refusing to build unredacted snapshot: pass BOTH --redact=false and --confirm-unredacted to explicitly confirm unredacted publication")
	}

	sourceAbs, err := filepath.Abs(opts.Source)
	if err != nil {
		return nil, fmt.Errorf("resolve --source %q: %w", opts.Source, err)
	}
	sourceInfo, err := os.Stat(sourceAbs)
	if err != nil {
		return nil, fmt.Errorf("stat --source %q: %w", sourceAbs, err)
	}

	outAbs, err := filepath.Abs(opts.Out)
	if err != nil {
		return nil, fmt.Errorf("resolve --out %q: %w", opts.Out, err)
	}
	if sameOrNestedPath(sourceAbs, outAbs) {
		return nil, fmt.Errorf("--out %q must not overlap --source %q", outAbs, sourceAbs)
	}
	if err := checkOutputDirBeforeStage(outAbs, opts.Force); err != nil {
		return nil, err
	}

	snapshotID := strings.TrimSpace(opts.SnapshotID)
	nowUTC := time.Now().UTC()
	if snapshotID == "" {
		snapshotID = "snapshot-" + nowUTC.Format("20060102T150405Z")
	}
	if !snapshotIDPattern.MatchString(snapshotID) {
		return nil, fmt.Errorf("invalid --snapshot-id %q (must match %s)", snapshotID, snapshotIDPattern.String())
	}

	// Stage inside a temporary sibling directory of --out (ensuring atomic/clean publish and zero partial output on error).
	if err := os.MkdirAll(filepath.Dir(outAbs), 0o755); err != nil {
		return nil, fmt.Errorf("create parent directory for --out: %w", err)
	}
	stageDir, err := os.MkdirTemp(filepath.Dir(outAbs), ".vpro-snapshot-stage-*")
	if err != nil {
		return nil, fmt.Errorf("create staging directory: %w", err)
	}
	cleanupStage := true
	defer func() {
		if cleanupStage {
			_ = os.RemoveAll(stageDir)
		}
	}()

	stageFamilyDir := filepath.Join(stageDir, vprocore.DatabaseFamilySubdir)
	stageProjectsDir := filepath.Join(stageDir, "projects")
	if err := os.MkdirAll(stageFamilyDir, 0o755); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(stageProjectsDir, 0o755); err != nil {
		return nil, err
	}

	// 1. Stage all 5 VP08 support databases without mutating any source files.
	supportDir := ""
	if strings.TrimSpace(opts.SupportDir) != "" {
		supportDir, err = filepath.Abs(opts.SupportDir)
		if err != nil {
			return nil, fmt.Errorf("resolve --support-dir: %w", err)
		}
	} else if sourceInfo.IsDir() {
		supportDir = sourceAbs
	}

	stagedSupport, err := stageSupportFamily(ctx, stageFamilyDir, opts.VLists, supportDir)
	if err != nil {
		return nil, err
	}

	// 2. Fail-closed Red/Blue-listed species metadata check BEFORE processing project DBs.
	var sensitiveSpecies map[string]struct{}
	redBlueSpeciesCount := 0
	if opts.Redact {
		sensitiveSpecies, err = RequireSensitiveSpecies(ctx, stagedSupport["VLists"], false)
		if err != nil {
			return nil, err
		}
		redBlueSpeciesCount = len(sensitiveSpecies)
	} else {
		if meta, loadErr := LoadSensitiveSpecies(ctx, stagedSupport["VLists"], false); loadErr == nil {
			redBlueSpeciesCount = len(meta.Codes)
		}
	}

	// 3. Stage source project (and optional sibling hierarchy) .db files without mutating sources.
	sourceDBs, err := collectSourceDBFiles(sourceAbs, sourceInfo)
	if err != nil {
		return nil, err
	}
	if len(sourceDBs) == 0 {
		return nil, fmt.Errorf("no .db files found in --source %q", sourceAbs)
	}

	type stagedProjectFile struct {
		fileName        string
		absPath         string
		relPath         string
		projects        []string
		redactedPerProj map[string]int
	}

	stagedProjectFiles := make([]stagedProjectFile, 0, len(sourceDBs))
	auxiliaryFiles := map[string]string{} // relPath -> absPath

	for _, srcDB := range sourceDBs {
		baseName := filepath.Base(srcDB)
		dstPath := filepath.Join(stageProjectsDir, baseName)
		if err := copySQLiteWithSidecars(srcDB, dstPath); err != nil {
			return nil, fmt.Errorf("stage source database %q: %w", srcDB, err)
		}

		// If the copied DB had WAL sidecars, replay/checkpoint them first in staging so reads see all frames.
		if err := checkpointStagedDB(ctx, dstPath); err != nil {
			return nil, fmt.Errorf("checkpoint staged database %q: %w", baseName, err)
		}

		infos, err := vprocore.InspectFileContext(ctx, dstPath)
		if err != nil {
			return nil, fmt.Errorf("inspect staged database %q: %w", baseName, err)
		}
		var compatProjects []string
		for _, info := range infos {
			if info.Compatible {
				compatProjects = append(compatProjects, info.Name)
			}
		}

		if len(compatProjects) == 0 {
			// Check if this is a standalone compatible hierarchy-only .db (valid in --source dir).
			hiers, hErr := discoverHierarchiesInDB(ctx, dstPath, "projects/"+baseName, false)
			if hErr == nil && len(hiers) > 0 {
				auxiliaryFiles["projects/"+baseName] = dstPath
				continue
			}
			if !sourceInfo.IsDir() {
				return nil, fmt.Errorf("source database %q contains no compatible VP08 projects", srcDB)
			}
			// Ignore unrelated .db files inside a directory source.
			_ = sqlutil.RemoveSQLiteWithSidecars(dstPath)
			continue
		}

		redactedCounts := map[string]int{}
		if opts.Redact {
			redactedCounts, err = RedactProjectDatabase(ctx, dstPath, compatProjects, sensitiveSpecies)
			if err != nil {
				return nil, fmt.Errorf("redact %q: %w", baseName, err)
			}
		}
		if _, err := StripProjectAudit(ctx, dstPath, compatProjects); err != nil {
			return nil, fmt.Errorf("strip audit rows in %q: %w", baseName, err)
		}

		stagedProjectFiles = append(stagedProjectFiles, stagedProjectFile{
			fileName:        baseName,
			absPath:         dstPath,
			relPath:         "projects/" + baseName,
			projects:        compatProjects,
			redactedPerProj: redactedCounts,
		})
	}

	if len(stagedProjectFiles) == 0 {
		return nil, fmt.Errorf("no compatible VP08 projects found in --source %q", sourceAbs)
	}

	// 4. Finalize EVERY published .db (all 5 support DBs + all project & auxiliary DBs) for immutable read-only mounts.
	for _, seed := range vprocore.DatabaseFamilySeeds {
		if err := finalizeImmutableSQLite(ctx, stagedSupport[seed.Name]); err != nil {
			return nil, fmt.Errorf("finalize support database %s: %w", seed.Name, err)
		}
	}
	for _, pf := range stagedProjectFiles {
		if err := finalizeImmutableSQLite(ctx, pf.absPath); err != nil {
			return nil, fmt.Errorf("finalize project database %s: %w", pf.fileName, err)
		}
	}
	for rel, abs := range auxiliaryFiles {
		if err := finalizeImmutableSQLite(ctx, abs); err != nil {
			return nil, fmt.Errorf("finalize auxiliary database %s: %w", rel, err)
		}
	}

	// 5. Discover compatible *_Hierarchy tables across all finalized DBs in projects/.
	allHierarchies, err := discoverAllHierarchiesInDir(ctx, stageProjectsDir, true)
	if err != nil {
		return nil, fmt.Errorf("discover hierarchies: %w", err)
	}

	// 6. Hash support files and compute StandardsStamp.
	supportSpecs := make(map[string]SupportFileSpec, len(vprocore.DatabaseFamilySeeds))
	for _, seed := range vprocore.DatabaseFamilySeeds {
		absPath := stagedSupport[seed.Name]
		sum, size, err := ComputeFileSHA256(absPath)
		if err != nil {
			return nil, fmt.Errorf("hash support database %s: %w", seed.Name, err)
		}
		supportSpecs[seed.Name] = SupportFileSpec{
			File:      vprocore.DatabaseFamilySubdir + "/" + seed.Name + ".db",
			SHA256:    sum,
			SizeBytes: size,
		}
	}

	auxSpecs := map[string]SupportFileSpec{}
	for rel, absPath := range auxiliaryFiles {
		sum, size, err := ComputeFileSHA256(absPath)
		if err != nil {
			return nil, fmt.Errorf("hash auxiliary database %s: %w", rel, err)
		}
		auxSpecs[filepath.Base(absPath)] = SupportFileSpec{
			File:      rel,
			SHA256:    sum,
			SizeBytes: size,
		}
	}

	becVersion, taxonomyVersion, lmh25SHA := LoadEmbeddedStandardsBase()
	vlistsCounts, err := readVListsTableCounts(ctx, stagedSupport["VLists"], true)
	if err != nil {
		return nil, fmt.Errorf("read VLists.db table counts: %w", err)
	}
	standards := StandardsStamp{
		BECVersion:          becVersion,
		TaxonomyVersion:     taxonomyVersion,
		LMH25PDF2023SHA256:  lmh25SHA,
		VListsSHA256:        supportSpecs["VLists"].SHA256,
		RedBlueSpeciesCount: redBlueSpeciesCount,
		TableCounts:         vlistsCounts,
	}

	// 7. Build DatasetSpec slice with plot counts, compatible SUs, hierarchies, and SHA-256.
	totalProjectCount := 0
	for _, pf := range stagedProjectFiles {
		totalProjectCount += len(pf.projects)
	}

	datasets := make([]DatasetSpec, 0, totalProjectCount)
	usedIDs := map[string]bool{}
	totalRedactedPlots := 0

	for _, pf := range stagedProjectFiles {
		sum, size, err := ComputeFileSHA256(pf.absPath)
		if err != nil {
			return nil, fmt.Errorf("hash project database %s: %w", pf.fileName, err)
		}
		sus, err := discoverSUsInDB(ctx, pf.absPath, pf.relPath, true)
		if err != nil {
			return nil, fmt.Errorf("discover SUs in %s: %w", pf.fileName, err)
		}

		for _, project := range pf.projects {
			plotCount, err := countProjectPlots(ctx, pf.absPath, project, true)
			if err != nil {
				return nil, fmt.Errorf("count plots for %s in %s: %w", project, pf.fileName, err)
			}
			dsID := uniqueDatasetID(project, pf.fileName, usedIDs)
			label := project
			if trimmedLabel := strings.TrimSpace(opts.Label); trimmedLabel != "" {
				if totalProjectCount == 1 {
					label = trimmedLabel
				} else {
					label = fmt.Sprintf("%s (%s)", trimmedLabel, project)
				}
			}
			redactedCount := pf.redactedPerProj[project]
			totalRedactedPlots += redactedCount

			datasets = append(datasets, DatasetSpec{
				ID:                dsID,
				Label:             label,
				Project:           project,
				File:              pf.relPath,
				SHA256:            sum,
				SizeBytes:         size,
				PlotCount:         plotCount,
				RedactedPlotCount: redactedCount,
				SUs:               slices.Clone(sus),
				Hierarchies:       slices.Clone(allHierarchies),
			})
		}
	}

	manifest := &Manifest{
		SchemaVersion:     ManifestSchemaVersion,
		SnapshotID:        snapshotID,
		PublishedAt:       nowUTC.Format(time.RFC3339),
		Redacted:          opts.Redact,
		RedactedPlotCount: totalRedactedPlots,
		Standards:         standards,
		SupportFiles:      supportSpecs,
		Datasets:          datasets,
	}
	if len(auxSpecs) > 0 {
		manifest.AuxiliaryFiles = auxSpecs
	}

	manifestPath := filepath.Join(stageDir, ManifestFilename)
	if err := WriteManifest(manifestPath, manifest); err != nil {
		return nil, fmt.Errorf("write %s: %w", ManifestFilename, err)
	}

	// 8. Self-verify the staged bundle before publishing into --out.
	if _, err := VerifyBundle(ctx, stageDir); err != nil {
		return nil, fmt.Errorf("self-verify staged bundle failed: %w", err)
	}

	// Normalize permissions so read-only mounts with non-root container UIDs can read cleanly.
	if err := chmodBundleReadable(stageDir); err != nil {
		return nil, fmt.Errorf("set bundle permissions: %w", err)
	}

	// 9. Publish staged directory to --out.
	if err := publishStageToOut(stageDir, outAbs, opts.Force); err != nil {
		return nil, fmt.Errorf("publish bundle to %q: %w", outAbs, err)
	}
	cleanupStage = false
	return manifest, nil
}

// VerifyBundle validates every SHA-256 checksum, immutable SQLite openability (no -wal/-shm),
// VP08 schema integrity, zero-row <Project>_Audit tables, and fail-closed Red/Blue coordinate redaction.
// It performs zero writes and works on 0555 read-only directories / 0444 read-only files.
func VerifyBundle(ctx context.Context, bundleDir string) (*VerifyResult, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if strings.TrimSpace(bundleDir) == "" {
		return nil, errors.New("--bundle is required")
	}

	absBundle, err := filepath.Abs(bundleDir)
	if err != nil {
		return nil, fmt.Errorf("resolve --bundle %q: %w", bundleDir, err)
	}
	info, err := os.Stat(absBundle)
	if err != nil {
		return nil, fmt.Errorf("stat --bundle %q: %w", absBundle, err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("--bundle %q is not a directory", absBundle)
	}

	manifest, err := ReadManifest(filepath.Join(absBundle, ManifestFilename))
	if err != nil {
		return nil, err
	}

	// Verify no stray SQLite WAL/SHM/journal sidecar files exist anywhere in database-family/ or projects/.
	for _, sub := range []string{vprocore.DatabaseFamilySubdir, "projects"} {
		subDir := filepath.Join(absBundle, sub)
		entries, err := os.ReadDir(subDir)
		if err != nil {
			return nil, fmt.Errorf("read bundle subdirectory %q: %w", sub, err)
		}
		for _, entry := range entries {
			lower := strings.ToLower(entry.Name())
			if strings.HasSuffix(lower, "-wal") || strings.HasSuffix(lower, "-shm") || strings.HasSuffix(lower, "-journal") {
				return nil, fmt.Errorf("prohibited SQLite sidecar file present in immutable bundle: %s/%s", sub, entry.Name())
			}
		}
	}

	// Collect all unique bundle-relative files and expected SHA-256 hashes to verify.
	type fileExpectation struct {
		relPath   string
		sha256    string
		sizeBytes int64
	}
	expectedFiles := map[string]fileExpectation{}
	addExpected := func(rel, hash string, size int64) error {
		if prev, ok := expectedFiles[rel]; ok {
			if prev.sha256 != hash {
				return fmt.Errorf("conflicting expected SHA-256 for %q", rel)
			}
			return nil
		}
		expectedFiles[rel] = fileExpectation{relPath: rel, sha256: hash, sizeBytes: size}
		return nil
	}

	supportAbsPaths := make(map[string]string, len(manifest.SupportFiles))
	for role, spec := range manifest.SupportFiles {
		if err := addExpected(spec.File, spec.SHA256, spec.SizeBytes); err != nil {
			return nil, err
		}
		absPath, err := SafeBundleRelPath(absBundle, spec.File)
		if err != nil {
			return nil, fmt.Errorf("supportFiles[%s]: %w", role, err)
		}
		supportAbsPaths[role] = absPath
	}
	for key, spec := range manifest.AuxiliaryFiles {
		if err := addExpected(spec.File, spec.SHA256, spec.SizeBytes); err != nil {
			return nil, err
		}
		if _, err := SafeBundleRelPath(absBundle, spec.File); err != nil {
			return nil, fmt.Errorf("auxiliaryFiles[%s]: %w", key, err)
		}
	}
	for _, ds := range manifest.Datasets {
		if err := addExpected(ds.File, ds.SHA256, ds.SizeBytes); err != nil {
			return nil, err
		}
	}

	relPaths := make([]string, 0, len(expectedFiles))
	for rel := range expectedFiles {
		relPaths = append(relPaths, rel)
	}
	slices.Sort(relPaths)

	// Verify SHA-256, non-sidecar status, non-WAL SQLite header, and immutable read-only openability for every file.
	for _, rel := range relPaths {
		exp := expectedFiles[rel]
		absPath, err := SafeBundleRelPath(absBundle, rel)
		if err != nil {
			return nil, err
		}
		st, err := os.Stat(absPath)
		if err != nil {
			return nil, fmt.Errorf("stat %s: %w", rel, err)
		}
		if !st.Mode().IsRegular() {
			return nil, fmt.Errorf("%s is not a regular file", rel)
		}
		sum, size, err := ComputeFileSHA256(absPath)
		if err != nil {
			return nil, fmt.Errorf("hash %s: %w", rel, err)
		}
		if sum != exp.sha256 {
			return nil, fmt.Errorf("SHA-256 mismatch for %s: got %s, manifest expects %s", rel, sum, exp.sha256)
		}
		if exp.sizeBytes > 0 && size != exp.sizeBytes {
			return nil, fmt.Errorf("size mismatch for %s: got %d bytes, manifest expects %d", rel, size, exp.sizeBytes)
		}
		if err := verifySQLiteImmutableFile(ctx, absPath); err != nil {
			return nil, fmt.Errorf("immutable SQLite check failed for %s: %w", rel, err)
		}
	}

	// Validate required tables in all 5 support DBs using immutable read-only connections.
	for _, seed := range vprocore.DatabaseFamilySeeds {
		if err := verifySupportDatabaseSchema(ctx, seed.Name, supportAbsPaths[seed.Name], true); err != nil {
			return nil, err
		}
	}

	// If manifest claims redacted=true, load Red/Blue conservation status metadata fail-closed.
	var sensitiveSpecies map[string]struct{}
	if manifest.Redacted {
		sensitiveSpecies, err = RequireSensitiveSpecies(ctx, supportAbsPaths["VLists"], true)
		if err != nil {
			return nil, fmt.Errorf("verify redacted snapshot conservation metadata: %w", err)
		}
	}

	verifiedDatasets := make([]string, 0, len(manifest.Datasets))
	totalObservedRedacted := 0

	for _, ds := range manifest.Datasets {
		projectAbsPath, err := SafeBundleRelPath(absBundle, ds.File)
		if err != nil {
			return nil, fmt.Errorf("dataset %s: %w", ds.ID, err)
		}

		// Full VP08 schema integrity + read-only immutable attachment test.
		if err := verifyVP08ProjectSchemaImmutable(ctx, ds.Project, projectAbsPath, supportAbsPaths); err != nil {
			return nil, fmt.Errorf("dataset %s (%s): %w", ds.ID, ds.Project, err)
		}

		projDB, err := openSQLiteReadOnly(ctx, projectAbsPath, true)
		if err != nil {
			return nil, fmt.Errorf("dataset %s: open immutable project DB: %w", ds.ID, err)
		}

		// Verify plotCount matches <Project>_Env.
		var actualPlots int
		envTbl := vprocore.QuoteHeaderIdentifier(ds.Project + "_Env")
		if err := projDB.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+envTbl).Scan(&actualPlots); err != nil {
			_ = projDB.Close()
			return nil, fmt.Errorf("dataset %s: count %s_Env: %w", ds.ID, ds.Project, err)
		}
		if actualPlots != ds.PlotCount {
			_ = projDB.Close()
			return nil, fmt.Errorf("dataset %s: plotCount mismatch: DB has %d plots, manifest records %d", ds.ID, actualPlots, ds.PlotCount)
		}

		// Verify <Project>_Audit has exactly 0 rows.
		var auditRows int
		auditTbl := vprocore.QuoteHeaderIdentifier(ds.Project + "_Audit")
		if err := projDB.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+auditTbl).Scan(&auditRows); err != nil {
			_ = projDB.Close()
			return nil, fmt.Errorf("dataset %s: count %s_Audit: %w", ds.ID, ds.Project, err)
		}
		if auditRows != 0 {
			_ = projDB.Close()
			return nil, fmt.Errorf("dataset %s: %s_Audit contains %d rows (must be 0 for read-only web snapshot)", ds.ID, ds.Project, auditRows)
		}

		// Verify zero unredacted sensitive coordinates remain when redacted=true.
		if manifest.Redacted {
			observedRedacted, err := VerifyProjectRedaction(ctx, projDB, ds.Project, sensitiveSpecies)
			if err != nil {
				_ = projDB.Close()
				return nil, fmt.Errorf("dataset %s: %w", ds.ID, err)
			}
			if observedRedacted != ds.RedactedPlotCount {
				_ = projDB.Close()
				return nil, fmt.Errorf("dataset %s: redactedPlotCount mismatch: DB has %d sensitive plots, manifest records %d",
					ds.ID, observedRedacted, ds.RedactedPlotCount)
			}
			totalObservedRedacted += observedRedacted
		}
		_ = projDB.Close()

		// Verify all declared SUs are compatible in their referenced files.
		for _, su := range ds.SUs {
			suAbs, err := SafeBundleRelPath(absBundle, su.File)
			if err != nil {
				return nil, fmt.Errorf("dataset %s SU %s: %w", ds.ID, su.Name, err)
			}
			if err := verifyCompatibleSU(ctx, suAbs, su.Name, true); err != nil {
				return nil, fmt.Errorf("dataset %s SU %s: %w", ds.ID, su.Name, err)
			}
		}

		// Verify all declared Hierarchies are compatible in their referenced files.
		for _, h := range ds.Hierarchies {
			hAbs, err := SafeBundleRelPath(absBundle, h.File)
			if err != nil {
				return nil, fmt.Errorf("dataset %s hierarchy %s: %w", ds.ID, h.Name, err)
			}
			if err := verifyCompatibleHierarchy(ctx, hAbs, h.Name, true); err != nil {
				return nil, fmt.Errorf("dataset %s hierarchy %s: %w", ds.ID, h.Name, err)
			}
		}

		verifiedDatasets = append(verifiedDatasets, ds.ID)
	}

	if manifest.Redacted && totalObservedRedacted != manifest.RedactedPlotCount {
		return nil, fmt.Errorf("manifest redactedPlotCount (%d) does not match observed total (%d)",
			manifest.RedactedPlotCount, totalObservedRedacted)
	}

	return &VerifyResult{
		SnapshotID:        manifest.SnapshotID,
		DatasetCount:      len(manifest.Datasets),
		SupportFileCount:  len(manifest.SupportFiles),
		Redacted:          manifest.Redacted,
		RedactedPlotCount: manifest.RedactedPlotCount,
		VerifiedFiles:     relPaths,
		VerifiedDatasets:  verifiedDatasets,
	}, nil
}

func stageSupportFamily(ctx context.Context, stageFamilyDir, explicitVLists, supportDir string) (map[string]string, error) {
	staged := make(map[string]string, len(vprocore.DatabaseFamilySeeds))
	var seedTempDir string
	var embeddedSeeds map[string]string
	defer func() {
		if seedTempDir != "" {
			_ = os.RemoveAll(seedTempDir)
		}
	}()

	ensureEmbeddedSeeds := func() (map[string]string, error) {
		if embeddedSeeds != nil {
			return embeddedSeeds, nil
		}
		tmpDir, err := os.MkdirTemp("", "vpro-snapshot-seeds-*")
		if err != nil {
			return nil, err
		}
		seedTempDir = tmpDir
		paths, err := vprocore.InstallDatabaseFamily(tmpDir)
		if err != nil {
			return nil, fmt.Errorf("extract embedded VP08 support database seeds: %w", err)
		}
		embeddedSeeds = paths
		return embeddedSeeds, nil
	}

	for _, seed := range vprocore.DatabaseFamilySeeds {
		var srcPath string
		if seed.Name == "VLists" && strings.TrimSpace(explicitVLists) != "" {
			absVLists, err := filepath.Abs(explicitVLists)
			if err != nil {
				return nil, fmt.Errorf("resolve --vlists %q: %w", explicitVLists, err)
			}
			st, err := os.Stat(absVLists)
			if err != nil || !st.Mode().IsRegular() {
				return nil, fmt.Errorf("--vlists %q does not exist or is not a regular file", absVLists)
			}
			srcPath = absVLists
		} else if supportDir != "" {
			if resolved, err := vprocore.ResolveWorkspaceSupportDatabase(supportDir, seed.Name); err == nil {
				srcPath = resolved
			}
		}

		if srcPath == "" {
			seeds, err := ensureEmbeddedSeeds()
			if err != nil {
				return nil, err
			}
			srcPath = seeds[seed.Name]
		}

		dstPath := filepath.Join(stageFamilyDir, seed.Name+".db")
		if err := copySQLiteWithSidecars(srcPath, dstPath); err != nil {
			return nil, fmt.Errorf("stage support database %s from %q: %w", seed.Name, srcPath, err)
		}
		if err := checkpointStagedDB(ctx, dstPath); err != nil {
			return nil, fmt.Errorf("checkpoint staged support database %s: %w", seed.Name, err)
		}
		if err := verifySupportDatabaseSchema(ctx, seed.Name, dstPath, false); err != nil {
			return nil, fmt.Errorf("invalid support database %s (%q): %w", seed.Name, srcPath, err)
		}
		staged[seed.Name] = dstPath
	}

	return staged, nil
}

func verifySupportDatabaseSchema(ctx context.Context, role, dbPath string, immutable bool) error {
	reqTables, ok := requiredSupportTables[role]
	if !ok {
		return fmt.Errorf("unknown VP08 support database role %q", role)
	}
	db, err := openSQLiteReadOnly(ctx, dbPath, immutable)
	if err != nil {
		return fmt.Errorf("open support database %s: %w", role, err)
	}
	defer db.Close()

	for _, tbl := range reqTables {
		var exists bool
		if err := db.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, tbl,
		).Scan(&exists); err != nil {
			return fmt.Errorf("check %s.%s: %w", role, tbl, err)
		}
		if !exists {
			return fmt.Errorf("support database %s is missing required VP08 table %s", role, tbl)
		}
	}
	if role == "VLists" {
		cols, err := tableColumns(ctx, db, "USysAllSpecs")
		if err != nil {
			return fmt.Errorf("inspect VLists.USysAllSpecs: %w", err)
		}
		for _, req := range []string{"EnglishName", "CombinedEnglishName"} {
			if !cols[req] {
				return fmt.Errorf("VLists.USysAllSpecs is missing required column %s", req)
			}
		}
	}
	return nil
}

func collectSourceDBFiles(sourceAbs string, sourceInfo os.FileInfo) ([]string, error) {
	if !sourceInfo.IsDir() {
		if !sourceInfo.Mode().IsRegular() {
			return nil, fmt.Errorf("--source %q is not a regular file or directory", sourceAbs)
		}
		if !strings.EqualFold(filepath.Ext(sourceAbs), ".db") {
			return nil, fmt.Errorf("--source file %q must have a .db extension", sourceAbs)
		}
		return []string{sourceAbs}, nil
	}

	seenBase := map[string]string{}
	var collected []string
	addDir := func(dir string, skipSupportNames bool) error {
		entries, err := os.ReadDir(dir)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return nil
			}
			return err
		}
		for _, entry := range entries {
			if entry.IsDir() || !strings.EqualFold(filepath.Ext(entry.Name()), ".db") {
				continue
			}
			lower := strings.ToLower(entry.Name())
			if skipSupportNames && canonicalSupportFileNames[lower] {
				continue
			}
			full := filepath.Join(dir, entry.Name())
			st, err := os.Stat(full)
			if err != nil || !st.Mode().IsRegular() {
				continue
			}
			if prev, dup := seenBase[lower]; dup {
				return fmt.Errorf("duplicate source database filename %q (%q and %q)", entry.Name(), prev, full)
			}
			seenBase[lower] = full
			collected = append(collected, full)
		}
		return nil
	}

	// Prefer <source>/projects/*.db plus top-level <source>/*.db (excluding support DB filenames).
	if err := addDir(filepath.Join(sourceAbs, "projects"), false); err != nil {
		return nil, err
	}
	if err := addDir(sourceAbs, true); err != nil {
		return nil, err
	}
	slices.Sort(collected)
	return collected, nil
}

// copySQLiteWithSidecars copies a SQLite .db file and any accompanying -wal/-shm sidecars
// into dstPath without ever opening source files for writing.
func copySQLiteWithSidecars(srcPath, dstPath string) error {
	if err := copyFileReadOnly(srcPath, dstPath, 0o644); err != nil {
		return err
	}
	for _, suffix := range []string{"-wal", "-shm"} {
		if _, err := os.Stat(srcPath + suffix); err == nil {
			if err := copyFileReadOnly(srcPath+suffix, dstPath+suffix, 0o644); err != nil {
				return fmt.Errorf("copy %s sidecar: %w", suffix, err)
			}
		}
	}
	return nil
}

func copyFileReadOnly(srcPath, dstPath string, perm os.FileMode) error {
	src, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer src.Close()

	dst, err := os.OpenFile(dstPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	if _, err := io.Copy(dst, src); err != nil {
		_ = dst.Close()
		return err
	}
	if err := dst.Sync(); err != nil {
		_ = dst.Close()
		return err
	}
	return dst.Close()
}

func checkpointStagedDB(ctx context.Context, dbPath string) error {
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rw")+"&_busy_timeout=5000")
	if err != nil {
		return err
	}
	db.SetMaxOpenConns(1)
	defer db.Close()

	var busy, logFrames, checkpointed int
	if err := db.QueryRowContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE);`).Scan(&busy, &logFrames, &checkpointed); err != nil {
		return fmt.Errorf("PRAGMA wal_checkpoint(TRUNCATE): %w", err)
	}
	if busy != 0 {
		return fmt.Errorf("PRAGMA wal_checkpoint(TRUNCATE) blocked (busy=%d)", busy)
	}
	return nil
}

// finalizeImmutableSQLite checkpoints WAL, switches journal_mode to DELETE, runs ANALYZE & VACUUM,
// removes any -wal/-shm/-journal sidecars, and verifies mode=ro&immutable=1 openability.
func finalizeImmutableSQLite(ctx context.Context, dbPath string) error {
	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(dbPath, "rw")+"&_busy_timeout=5000")
	if err != nil {
		return err
	}
	db.SetMaxOpenConns(1)

	var busy, logFrames, checkpointed int
	if err := db.QueryRowContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE);`).Scan(&busy, &logFrames, &checkpointed); err != nil {
		_ = db.Close()
		return fmt.Errorf("PRAGMA wal_checkpoint(TRUNCATE): %w", err)
	}
	if busy != 0 {
		_ = db.Close()
		return fmt.Errorf("PRAGMA wal_checkpoint(TRUNCATE) left busy=%d", busy)
	}

	var mode string
	if err := db.QueryRowContext(ctx, `PRAGMA journal_mode = DELETE;`).Scan(&mode); err != nil {
		_ = db.Close()
		return fmt.Errorf("PRAGMA journal_mode = DELETE: %w", err)
	}
	if !strings.EqualFold(strings.TrimSpace(mode), "delete") {
		_ = db.Close()
		return fmt.Errorf("expected journal_mode=delete, got %q", mode)
	}

	if _, err := db.ExecContext(ctx, `ANALYZE;`); err != nil {
		_ = db.Close()
		return fmt.Errorf("ANALYZE: %w", err)
	}
	if _, err := db.ExecContext(ctx, `VACUUM;`); err != nil {
		_ = db.Close()
		return fmt.Errorf("VACUUM: %w", err)
	}
	if err := db.Close(); err != nil {
		return fmt.Errorf("close finalized SQLite DB: %w", err)
	}

	for _, suffix := range []string{"-wal", "-shm", "-journal"} {
		if err := os.Remove(dbPath + suffix); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove sidecar %s: %w", suffix, err)
		}
	}

	return verifySQLiteImmutableFile(ctx, dbPath)
}

func verifySQLiteImmutableFile(ctx context.Context, dbPath string) error {
	for _, suffix := range []string{"-wal", "-shm", "-journal"} {
		if _, err := os.Stat(dbPath + suffix); err == nil {
			return fmt.Errorf("sidecar file %s still exists next to %s", suffix, filepath.Base(dbPath))
		}
	}

	f, err := os.Open(dbPath)
	if err != nil {
		return err
	}
	var hdr [100]byte
	_, readErr := io.ReadFull(f, hdr[:])
	_ = f.Close()
	if readErr != nil {
		return fmt.Errorf("read SQLite header: %w", readErr)
	}
	if !bytes.Equal(hdr[:16], sqliteHeaderMagic) {
		return errors.New("file does not have a valid SQLite 3 header")
	}
	// Bytes 18 and 19 are file format write/read versions: 1/1 = legacy rollback journal, 2/2 = WAL.
	if hdr[18] != 1 || hdr[19] != 1 {
		return fmt.Errorf("SQLite header journal format version is (%d,%d); expected (1,1) DELETE rollback mode rather than WAL", hdr[18], hdr[19])
	}

	db, err := openSQLiteReadOnly(ctx, dbPath, true)
	if err != nil {
		return fmt.Errorf("open with mode=ro&immutable=1: %w", err)
	}
	defer db.Close()

	var masterCount int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM sqlite_master`).Scan(&masterCount); err != nil {
		return fmt.Errorf("query sqlite_master under immutable=1: %w", err)
	}
	var qc string
	if err := db.QueryRowContext(ctx, `PRAGMA quick_check`).Scan(&qc); err != nil {
		return fmt.Errorf("PRAGMA quick_check under immutable=1: %w", err)
	}
	if !strings.EqualFold(strings.TrimSpace(qc), "ok") {
		return fmt.Errorf("PRAGMA quick_check returned %q", qc)
	}
	return nil
}

func verifyVP08ProjectSchemaImmutable(ctx context.Context, project, projectPath string, supportPaths map[string]string) error {
	if !vprocore.ProjectNamePattern.MatchString(project) {
		return fmt.Errorf("invalid VP08 project name %q", project)
	}
	memDB, err := sqlutil.OpenMemorySQLite()
	if err != nil {
		return err
	}
	defer memDB.Close()

	conn, err := memDB.Conn(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()

	attachImmutable := func(alias, path string) error {
		uri := sqlutil.SqliteFileURI(path, "ro") + "&immutable=1"
		_, err := conn.ExecContext(ctx, `ATTACH DATABASE ? AS `+vprocore.QuoteHeaderIdentifier(alias), uri)
		return err
	}

	for _, seed := range vprocore.DatabaseFamilySeeds {
		if err := attachImmutable(seed.Name, supportPaths[seed.Name]); err != nil {
			return fmt.Errorf("attach immutable %s: %w", seed.Name, err)
		}
	}
	if err := attachImmutable("project", projectPath); err != nil {
		return fmt.Errorf("attach immutable project: %w", err)
	}

	// Verify all 8 core VP08 tables exist as physical tables.
	for _, suffix := range vprocore.CoreTables {
		tbl := project + "_" + suffix
		var exists bool
		if err := conn.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM "project".sqlite_master WHERE type='table' AND name=?)`, tbl,
		).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return fmt.Errorf("project %s is missing required VP08 table %s", project, tbl)
		}
	}

	// Verify _table_metadata has one unambiguous 'VP08' description for <Project>_Env.
	var hasMeta bool
	if err := conn.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM "project".sqlite_master WHERE type='table' AND name='_table_metadata')`,
	).Scan(&hasMeta); err != nil {
		return err
	}
	if !hasMeta {
		return fmt.Errorf("project %s is missing _table_metadata table", project)
	}
	metaRows, err := conn.QueryContext(ctx,
		`SELECT description FROM "project"._table_metadata WHERE table_name = ?`, project+"_Env",
	)
	if err != nil {
		return err
	}
	var versions []string
	for metaRows.Next() {
		var desc sql.NullString
		if err := metaRows.Scan(&desc); err != nil {
			_ = metaRows.Close()
			return err
		}
		if desc.Valid {
			versions = append(versions, desc.String)
		} else {
			versions = append(versions, "")
		}
	}
	if err := errors.Join(metaRows.Err(), metaRows.Close()); err != nil {
		return err
	}
	if len(versions) != 1 || versions[0] != "VP08" {
		return fmt.Errorf("project %s requires one unambiguous VP08 Env description; found %v", project, versions)
	}

	// Verify all required VP08 columns matching vprocore.SqliteContext.validateProject + Veg views.
	required := map[string][]string{
		"Admin":    {"Plot"},
		"Audit":    {"Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "BeforeEdit", "AfterEdit", "Restore", "Flag", "ID"},
		"Humus":    {"ID", "PlotNumber"},
		"Mineral":  {"ID", "PlotNumber"},
		"Other":    {"ID", "PlotNumber"},
		"Metadata": {"ID", "ProjectID"},
		"Veg":      requiredVegColumns,
	}
	for _, field := range vprocore.HeaderFields {
		if field.Table != "" && field.Column != "" {
			required[field.Table] = append(required[field.Table], field.Column)
		}
	}

	for suffix, reqCols := range required {
		tbl := project + "_" + suffix
		rows, err := conn.QueryContext(ctx, `PRAGMA "project".table_info(`+vprocore.QuoteHeaderIdentifier(tbl)+`)`)
		if err != nil {
			return err
		}
		present := map[string]bool{}
		for rows.Next() {
			var cid, notNull, pk int
			var name, colType string
			var dflt sql.NullString
			if err := rows.Scan(&cid, &name, &colType, &notNull, &dflt, &pk); err != nil {
				_ = rows.Close()
				return err
			}
			present[name] = true
		}
		if err := errors.Join(rows.Err(), rows.Close()); err != nil {
			return err
		}
		for _, col := range reqCols {
			if !present[col] {
				return fmt.Errorf("project.%s is missing required VP08 column %s", tbl, col)
			}
		}
	}
	return nil
}

func discoverSUsInDB(ctx context.Context, dbPath, relFile string, immutable bool) ([]SUEntry, error) {
	db, err := openSQLiteReadOnly(ctx, dbPath, immutable)
	if err != nil {
		return nil, err
	}
	defer db.Close()

	rows, err := db.QueryContext(ctx, `SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%_SU'`)
	if err != nil {
		return nil, err
	}
	var names []string
	for rows.Next() {
		var tbl string
		if err := rows.Scan(&tbl); err != nil {
			_ = rows.Close()
			return nil, err
		}
		if name, ok := strings.CutSuffix(tbl, "_SU"); ok && vprocore.ProjectNamePattern.MatchString(name) {
			names = append(names, name)
		}
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, err
	}
	slices.Sort(names)

	var hasPolicy bool
	if err := db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '_vpro_su_policy')`,
	).Scan(&hasPolicy); err != nil {
		return nil, err
	}

	sus := make([]SUEntry, 0, len(names))
	for _, name := range names {
		entry, ok, err := inspectSUEntry(ctx, db, name, relFile, hasPolicy)
		if err != nil {
			return nil, err
		}
		if ok {
			sus = append(sus, entry)
		}
	}
	return sus, nil
}

func inspectSUEntry(ctx context.Context, db *sql.DB, name, relFile string, hasPolicy bool) (SUEntry, bool, error) {
	kind := "ordinary"
	if hasPolicy {
		err := db.QueryRowContext(ctx, `SELECT kind FROM _vpro_su_policy WHERE table_name = ?`, name+"_SU").Scan(&kind)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return SUEntry{}, false, err
		}
		if errors.Is(err, sql.ErrNoRows) {
			kind = "ordinary"
		}
	}
	if kind != "ordinary" && kind != "working" {
		return SUEntry{}, false, nil
	}

	rows, err := db.QueryContext(ctx, `PRAGMA table_info(`+vprocore.QuoteHeaderIdentifier(name+"_SU")+`)`)
	if err != nil {
		return SUEntry{}, false, err
	}
	validText := map[string]bool{}
	for rows.Next() {
		var cid, notNull, pk int
		var colName, colType string
		var dflt sql.NullString
		if err := rows.Scan(&cid, &colName, &colType, &notNull, &dflt, &pk); err != nil {
			_ = rows.Close()
			return SUEntry{}, false, err
		}
		upper := strings.ToUpper(colType)
		validText[colName] = strings.Contains(upper, "CHAR") || strings.Contains(upper, "CLOB") || strings.Contains(upper, "TEXT")
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return SUEntry{}, false, err
	}
	if !validText["PlotNumber"] || !validText["SiteUnit"] {
		return SUEntry{}, false, nil
	}
	return SUEntry{
		Name:       name,
		Kind:       kind,
		File:       relFile,
		Compatible: true,
	}, true, nil
}

func verifyCompatibleSU(ctx context.Context, dbPath, name string, immutable bool) error {
	db, err := openSQLiteReadOnly(ctx, dbPath, immutable)
	if err != nil {
		return err
	}
	defer db.Close()

	var exists bool
	if err := db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, name+"_SU",
	).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return fmt.Errorf("SU table %s_SU does not exist", name)
	}
	var hasPolicy bool
	if err := db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '_vpro_su_policy')`,
	).Scan(&hasPolicy); err != nil {
		return err
	}
	_, ok, err := inspectSUEntry(ctx, db, name, "", hasPolicy)
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("SU table %s_SU is not compatible or not authorized", name)
	}
	return nil
}

func discoverAllHierarchiesInDir(ctx context.Context, projectsDir string, immutable bool) ([]HierarchyEntry, error) {
	entries, err := os.ReadDir(projectsDir)
	if err != nil {
		return nil, err
	}
	var all []HierarchyEntry
	for _, entry := range entries {
		if entry.IsDir() || !strings.EqualFold(filepath.Ext(entry.Name()), ".db") {
			continue
		}
		found, err := discoverHierarchiesInDB(ctx, filepath.Join(projectsDir, entry.Name()), "projects/"+entry.Name(), immutable)
		if err != nil {
			return nil, err
		}
		all = append(all, found...)
	}
	slices.SortFunc(all, func(a, b HierarchyEntry) int {
		if c := strings.Compare(a.Name, b.Name); c != 0 {
			return c
		}
		return strings.Compare(a.File, b.File)
	})
	return all, nil
}

func discoverHierarchiesInDB(ctx context.Context, dbPath, relFile string, immutable bool) ([]HierarchyEntry, error) {
	db, err := openSQLiteReadOnly(ctx, dbPath, immutable)
	if err != nil {
		return nil, err
	}
	defer db.Close()

	rows, err := db.QueryContext(ctx, `SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%_Hierarchy'`)
	if err != nil {
		return nil, err
	}
	var tables []string
	for rows.Next() {
		var tbl string
		if err := rows.Scan(&tbl); err != nil {
			_ = rows.Close()
			return nil, err
		}
		if name, ok := strings.CutSuffix(tbl, "_Hierarchy"); ok && vprocore.ProjectNamePattern.MatchString(name) {
			tables = append(tables, tbl)
		}
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, err
	}

	var hasMeta bool
	if err := db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '_table_metadata')`,
	).Scan(&hasMeta); err != nil {
		return nil, err
	}

	out := make([]HierarchyEntry, 0, len(tables))
	for _, tbl := range tables {
		name, _ := strings.CutSuffix(tbl, "_Hierarchy")
		compat, err := isHierarchyTableCompatible(ctx, db, tbl)
		if err != nil {
			return nil, err
		}
		if !compat {
			continue
		}
		ver := "Unknown"
		if hasMeta {
			var desc sql.NullString
			err := db.QueryRowContext(ctx, `SELECT description FROM _table_metadata WHERE table_name = ?`, tbl).Scan(&desc)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return nil, err
			}
			if desc.Valid && desc.String != "" {
				ver = desc.String
			}
		}
		out = append(out, HierarchyEntry{
			Name:       name,
			File:       relFile,
			Version:    ver,
			Compatible: true,
		})
	}
	return out, nil
}

func isHierarchyTableCompatible(ctx context.Context, db *sql.DB, table string) (bool, error) {
	rows, err := db.QueryContext(ctx, `PRAGMA table_info(`+vprocore.QuoteHeaderIdentifier(table)+`)`)
	if err != nil {
		return false, err
	}
	fields := map[string]string{}
	for rows.Next() {
		var cid, notNull, pk int
		var colName, colType string
		var dflt sql.NullString
		if err := rows.Scan(&cid, &colName, &colType, &notNull, &dflt, &pk); err != nil {
			_ = rows.Close()
			return false, err
		}
		fields[colName] = strings.ToUpper(colType)
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return false, err
	}
	return strings.Contains(fields["ID"], "INT") &&
		(strings.Contains(fields["Name"], "CHAR") || strings.Contains(fields["Name"], "CLOB") || strings.Contains(fields["Name"], "TEXT")) &&
		strings.Contains(fields["Parent"], "INT") &&
		strings.Contains(fields["Level"], "INT"), nil
}

func verifyCompatibleHierarchy(ctx context.Context, dbPath, name string, immutable bool) error {
	db, err := openSQLiteReadOnly(ctx, dbPath, immutable)
	if err != nil {
		return err
	}
	defer db.Close()

	tbl := name + "_Hierarchy"
	var exists bool
	if err := db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, tbl,
	).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return fmt.Errorf("hierarchy table %s does not exist", tbl)
	}
	compat, err := isHierarchyTableCompatible(ctx, db, tbl)
	if err != nil {
		return err
	}
	if !compat {
		return fmt.Errorf("hierarchy table %s requires integer ID/Parent/Level and text Name", tbl)
	}
	return nil
}

func countProjectPlots(ctx context.Context, dbPath, project string, immutable bool) (int, error) {
	db, err := openSQLiteReadOnly(ctx, dbPath, immutable)
	if err != nil {
		return 0, err
	}
	defer db.Close()

	var n int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(project+"_Env")).Scan(&n); err != nil {
		return 0, err
	}
	return n, nil
}

func readVListsTableCounts(ctx context.Context, vlistsPath string, immutable bool) (map[string]int, error) {
	db, err := openSQLiteReadOnly(ctx, vlistsPath, immutable)
	if err != nil {
		return nil, err
	}
	defer db.Close()

	targets := []string{"USysAllSpecs", "MasterSiteUnitList", "USysSiteSeriesNames", "USysZoneList", "USysTableOfLists", "USysSppAttributes"}
	counts := make(map[string]int, len(targets))
	for _, tbl := range targets {
		var exists bool
		if err := db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?)`, tbl).Scan(&exists); err != nil {
			return nil, err
		}
		if !exists {
			continue
		}
		var n int
		if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(tbl)).Scan(&n); err != nil {
			return nil, err
		}
		counts[tbl] = n
	}
	return counts, nil
}

func slugifyID(raw string) string {
	var b strings.Builder
	prevDash := false
	for _, r := range strings.ToLower(strings.TrimSpace(raw)) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
			prevDash = false
		} else if !prevDash && b.Len() > 0 {
			b.WriteByte('-')
			prevDash = true
		}
	}
	out := strings.TrimRight(b.String(), "-")
	if out == "" {
		return "dataset"
	}
	return out
}

func uniqueDatasetID(project, fileName string, used map[string]bool) string {
	base := slugifyID(project)
	if !used[base] {
		used[base] = true
		return base
	}
	stem := strings.TrimSuffix(fileName, filepath.Ext(fileName))
	candidate := slugifyID(stem + "-" + project)
	if !used[candidate] {
		used[candidate] = true
		return candidate
	}
	for i := 2; ; i++ {
		numbered := fmt.Sprintf("%s-%d", candidate, i)
		if !used[numbered] {
			used[numbered] = true
			return numbered
		}
	}
}

func isNestedWithin(parent, child string) bool {
	rel, err := filepath.Rel(parent, child)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func sameOrNestedPath(sourceAbs, outAbs string) bool {
	if sourceAbs == outAbs {
		return true
	}
	return isNestedWithin(sourceAbs, outAbs) || isNestedWithin(outAbs, sourceAbs)
}

func checkOutputDirBeforeStage(outAbs string, force bool) error {
	st, err := os.Stat(outAbs)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("stat --out %q: %w", outAbs, err)
	}
	if !st.IsDir() {
		return fmt.Errorf("--out %q exists and is not a directory", outAbs)
	}
	entries, err := os.ReadDir(outAbs)
	if err != nil {
		return fmt.Errorf("read --out %q: %w", outAbs, err)
	}
	if len(entries) > 0 && !force {
		return fmt.Errorf("--out directory %q is not empty (pass --force to replace an existing bundle)", outAbs)
	}
	return nil
}

func chmodBundleReadable(root string) error {
	return filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return os.Chmod(p, 0o755)
		}
		return os.Chmod(p, 0o644)
	})
}

func publishStageToOut(stageDir, outAbs string, force bool) error {
	st, err := os.Stat(outAbs)
	if errors.Is(err, os.ErrNotExist) {
		return os.Rename(stageDir, outAbs)
	}
	if err != nil {
		return err
	}
	if !st.IsDir() {
		return fmt.Errorf("--out %q is not a directory", outAbs)
	}
	existing, err := os.ReadDir(outAbs)
	if err != nil {
		return err
	}
	if len(existing) > 0 {
		if !force {
			return fmt.Errorf("--out directory %q is not empty", outAbs)
		}
		for _, entry := range existing {
			if err := os.RemoveAll(filepath.Join(outAbs, entry.Name())); err != nil {
				return err
			}
		}
	}
	stagedEntries, err := os.ReadDir(stageDir)
	if err != nil {
		return err
	}
	for _, entry := range stagedEntries {
		if err := os.Rename(filepath.Join(stageDir, entry.Name()), filepath.Join(outAbs, entry.Name())); err != nil {
			return err
		}
	}
	return os.RemoveAll(stageDir)
}
