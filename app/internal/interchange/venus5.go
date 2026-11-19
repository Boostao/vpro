package interchange

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/accessreader"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type VenusProjectCandidate struct {
	ProjectID         string `json:"projectId"`
	ProjectName       string `json:"projectName"`
	SuggestedTarget   string `json:"suggestedTarget"`
	SuggestedDestPath string `json:"suggestedDestPath"`
	PlotCount         int    `json:"plotCount"`
	VegObsCount       int    `json:"vegObsCount"`
	HumusRowCount     int    `json:"humusRowCount"`
	MineralRowCount   int    `json:"mineralRowCount"`
}

type VenusSourceInspection struct {
	SourcePath   string                  `json:"sourcePath"`
	SourceFormat string                  `json:"sourceFormat"` // "mdb" | "xml"
	VenusVersion string                  `json:"venusVersion"`
	SourceSHA256 string                  `json:"sourceSha256"`
	Projects     []VenusProjectCandidate `json:"projects"`
}

type VenusImportRequest struct {
	SourcePath        string `json:"sourcePath"`
	SourceProject     string `json:"sourceProject,omitempty"`
	TargetProject     string `json:"targetProject"`
	DestinationPath   string `json:"destinationPath,omitempty"`
	ActivateOnSuccess bool   `json:"activateOnSuccess"`
}

func (r *VenusImportRequest) UnmarshalJSON(data []byte) error {
	type plain VenusImportRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type VenusImportResult struct {
	SourcePath      string                 `json:"sourcePath"`
	SourceFormat    string                 `json:"sourceFormat"`
	VenusVersion    string                 `json:"venusVersion"`
	SourceProject   string                 `json:"sourceProject"`
	TargetProject   string                 `json:"targetProject"`
	DestinationPath string                 `json:"destinationPath"`
	DestinationSHA  string                 `json:"destinationSha256"`
	PlotCount       int                    `json:"plotCount"`
	VegRowCount     int                    `json:"vegRowCount"`
	HumusRowCount   int                    `json:"humusRowCount"`
	MineralRowCount int                    `json:"mineralRowCount"`
	Activated       bool                   `json:"activated"`
	State           *vprocore.ProjectState `json:"state,omitempty"`
}

type venusNormalizedArchive struct {
	Format   string
	Version  string
	SHA256   string
	Projects map[string]string // projectKey -> projectName
	Plots    []venusPlotRecord
}

type venusPlotRecord struct {
	PlotID          string
	ProjectKey      string
	ProjectName     string
	PlotQuality     string
	PlotNumber      string
	Graviti         bool
	Fields          map[string]string
	VegObservations []venusVegObs
	HumusRows       []map[string]string
	MineralRows     []map[string]string
}

type venusVegObs struct {
	Species   string
	Layer     string
	Cover     float64
	Height    *float64
	Collected string
}

func InspectVenusSource(s *vprocore.ContextService, ctx context.Context, contextID, sourcePath string) (VenusSourceInspection, error) {
	var projectsDir string
	if _, err := vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		projectsDir = filepath.Join(plots.Projects.Root, "projects")
		return struct{}{}, nil
	}); err != nil {
		return VenusSourceInspection{}, err
	}

	absPath, archive, err := loadVenusArchive(ctx, sourcePath)
	if err != nil {
		return VenusSourceInspection{}, err
	}

	byProj := map[string]*VenusProjectCandidate{}
	for _, pl := range archive.Plots {
		pName := strings.TrimSpace(pl.ProjectName)
		if pName == "" {
			pName = "VENUS5"
		}
		cand := byProj[pName]
		if cand == nil {
			suggested := sanitizeProjectSuggestion(pName)
			dest := filepath.Join(projectsDir, suggested+".db")
			cand = &VenusProjectCandidate{
				ProjectID:         pl.ProjectKey,
				ProjectName:       pName,
				SuggestedTarget:   suggested,
				SuggestedDestPath: dest,
			}
			byProj[pName] = cand
		}
		cand.PlotCount++
		cand.VegObsCount += len(pl.VegObservations)
		cand.HumusRowCount += len(pl.HumusRows)
		cand.MineralRowCount += len(pl.MineralRows)
	}

	list := make([]VenusProjectCandidate, 0, len(byProj))
	for _, c := range byProj {
		list = append(list, *c)
	}
	slices.SortFunc(list, func(a, b VenusProjectCandidate) int {
		return strings.Compare(a.ProjectName, b.ProjectName)
	})

	return VenusSourceInspection{
		SourcePath:   absPath,
		SourceFormat: archive.Format,
		VenusVersion: archive.Version,
		SourceSHA256: archive.SHA256,
		Projects:     list,
	}, nil
}

func ImportVenusProject(s *vprocore.ContextService, ctx context.Context, contextID string, request VenusImportRequest) (VenusImportResult, error) {
	absPath, archive, err := loadVenusArchive(ctx, request.SourcePath)
	if err != nil {
		return VenusImportResult{}, err
	}

	selectedProject := strings.TrimSpace(request.SourceProject)
	var filteredPlots []venusPlotRecord
	for _, pl := range archive.Plots {
		pName := strings.TrimSpace(pl.ProjectName)
		if pName == "" {
			pName = "VENUS5"
		}
		if selectedProject == "" || strings.EqualFold(selectedProject, pName) || strings.EqualFold(selectedProject, pl.ProjectKey) {
			if selectedProject == "" {
				selectedProject = pName
			}
			filteredPlots = append(filteredPlots, pl)
		}
	}
	if len(filteredPlots) == 0 {
		return VenusImportResult{}, fmt.Errorf("no VENUS plots matched project %q in %s", request.SourceProject, filepath.Base(absPath))
	}

	var vegRowsWritten, humusRowsWritten, mineralRowsWritten int
	destPath, destSHA, activated, newState, err := stageAndPublishVP08Project(
		s, ctx, contextID, request.TargetProject, request.DestinationPath, request.ActivateOnSuccess,
		func(ctx context.Context, tx *sql.Tx, targetProject string) error {
			var wErr error
			vegRowsWritten, humusRowsWritten, mineralRowsWritten, wErr = writeVenusToVP08Tx(ctx, tx, targetProject, selectedProject, archive.Version, filteredPlots)
			return wErr
		},
	)
	if err != nil {
		return VenusImportResult{}, err
	}

	// Verify source file was not mutated
	afterBytes, err := os.ReadFile(absPath)
	if err != nil {
		return VenusImportResult{}, err
	}
	afterHash := sha256.Sum256(afterBytes)
	if hex.EncodeToString(afterHash[:]) != archive.SHA256 {
		return VenusImportResult{}, errors.New("VENUS source file changed during import; publication aborted")
	}

	return VenusImportResult{
		SourcePath:      absPath,
		SourceFormat:    archive.Format,
		VenusVersion:    archive.Version,
		SourceProject:   selectedProject,
		TargetProject:   strings.TrimSpace(request.TargetProject),
		DestinationPath: destPath,
		DestinationSHA:  destSHA,
		PlotCount:       len(filteredPlots),
		VegRowCount:     vegRowsWritten,
		HumusRowCount:   humusRowsWritten,
		MineralRowCount: mineralRowsWritten,
		Activated:       activated,
		State:           newState,
	}, nil
}

func loadVenusArchive(ctx context.Context, sourcePath string) (string, venusNormalizedArchive, error) {
	if strings.TrimSpace(sourcePath) == "" || !utf8.ValidString(sourcePath) || strings.ContainsRune(sourcePath, 0) {
		return "", venusNormalizedArchive{}, errors.New("VENUS sourcePath must be a non-empty valid UTF-8 path")
	}
	abs, err := filepath.Abs(filepath.Clean(sourcePath))
	if err != nil {
		return "", venusNormalizedArchive{}, err
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if err != nil {
		return "", venusNormalizedArchive{}, fmt.Errorf("resolve VENUS source %q: %w", sourcePath, err)
	}
	rawBytes, err := os.ReadFile(resolved)
	if err != nil {
		return "", venusNormalizedArchive{}, err
	}
	sum := sha256.Sum256(rawBytes)
	shaHex := hex.EncodeToString(sum[:])

	ext := strings.ToLower(filepath.Ext(resolved))
	switch ext {
	case ".xml":
		arch, err := parseVenusXMLArchive(ctx, rawBytes, shaHex)
		return resolved, arch, err
	case ".mdb", ".accdb":
		arch, err := parseVenusAccessArchive(ctx, resolved, shaHex)
		return resolved, arch, err
	default:
		return "", venusNormalizedArchive{}, fmt.Errorf("unsupported VENUS file extension %q (expected .mdb, .accdb, or .xml)", ext)
	}
}

func validateVenus5PlusVersion(raw string) error {
	s := strings.TrimSpace(raw)
	if s == "" {
		return nil
	}
	end := 0
	seenDot := false
	for end < len(s) {
		ch := s[end]
		if ch >= '0' && ch <= '9' {
			end++
			continue
		}
		if ch == '.' && !seenDot {
			seenDot = true
			end++
			continue
		}
		break
	}
	if end == 0 {
		return fmt.Errorf("unsupported VENUS version %q (VENUS 5.0+ required)", raw)
	}
	verNum, err := strconv.ParseFloat(s[:end], 64)
	if err != nil {
		return fmt.Errorf("unsupported VENUS version %q (VENUS 5.0+ required)", raw)
	}
	if verNum < 5.0 {
		return fmt.Errorf("VENUS version %q is retired (< 5.0); upgrade to VENUS 5.0+ before import", raw)
	}
	return nil
}

func parseVenusAccessArchive(ctx context.Context, resolvedPath, shaHex string) (venusNormalizedArchive, error) {
	db, err := accessreader.Open(resolvedPath)
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("open VENUS Access database: %w", err)
	}
	tables, err := db.Tables()
	if err != nil {
		return venusNormalizedArchive{}, err
	}
	byLower := map[string]string{}
	for _, t := range tables {
		if !t.Linked {
			byLower[strings.ToLower(t.Name)] = t.Name
		}
	}

	readStringTable := func(candidates ...string) ([]map[string]string, bool, error) {
		for _, cand := range candidates {
			actual, ok := byLower[strings.ToLower(cand)]
			if !ok {
				continue
			}
			cols, rows, err := db.ReadAll(actual)
			if err != nil {
				return nil, false, err
			}
			adaptedIdx, adaptedRows, err := adaptAccessRows(ctx, cols, rows)
			if err != nil {
				return nil, false, err
			}
			out := make([]map[string]string, 0, len(adaptedRows))
			for _, r := range adaptedRows {
				m := make(map[string]string, len(adaptedIdx))
				for k, idx := range adaptedIdx {
					if r[idx] != nil {
						m[k] = strings.TrimSpace(fmt.Sprint(r[idx]))
					}
				}
				out = append(out, m)
			}
			return out, true, nil
		}
		return nil, false, nil
	}

	return parseVenusAccessTables(byLower, readStringTable, shaHex)
}

func parseVenusAccessTables(
	byLower map[string]string,
	readStringTable func(candidates ...string) ([]map[string]string, bool, error),
	shaHex string,
) (venusNormalizedArchive, error) {
	vRows, hasVer, err := readStringTable("USysVersion")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS USysVersion: %w", err)
	}
	version := "5.0"
	if hasVer && len(vRows) > 0 {
		if v := vRows[0]["version"]; v != "" {
			version = v
			if b := vRows[0]["beta"]; b != "" && b != "0" {
				version += "." + b
			}
		}
	}
	if err := validateVenus5PlusVersion(version); err != nil {
		return venusNormalizedArchive{}, err
	}

	if _, hasLegacyEnv := byLower["tblenv"]; hasLegacyEnv {
		_, hasPlotData := byLower["tblplotdata"]
		_, hasPlot := byLower["tblplot"]
		if !hasPlotData && !hasPlot {
			return venusNormalizedArchive{}, errors.New("VENUS 4.2 (tblEnv) archives are retired; VENUS 5.0+ (tblPlotData) is required")
		}
	}

	projRows, _, err := readStringTable("tblProjectManager", "tblProject")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblProjectManager: %w", err)
	}
	plotRows, hasPlotTbl, err := readStringTable("tblPlotData", "tblPlot")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblPlotData: %w", err)
	}
	if !hasPlotTbl {
		return venusNormalizedArchive{}, errors.New("VENUS database is missing tblPlotData / tblPlot")
	}
	soilRows, _, err := readStringTable("tblSoil")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblSoil: %w", err)
	}
	vegMainRows, _, err := readStringTable("tblVegMain")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblVegMain: %w", err)
	}
	vegLayerRows, _, err := readStringTable("tblVegLayer")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblVegLayer: %w", err)
	}
	vegSppRows, _, err := readStringTable("tblVegSpecies")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblVegSpecies: %w", err)
	}
	humusRows, _, err := readStringTable("tblOrganicHorizons", "tblSoilHumus")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblOrganicHorizons: %w", err)
	}
	mineralRows, _, err := readStringTable("tblMineralHorizons", "tblSoilMineral")
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("read VENUS tblMineralHorizons: %w", err)
	}

	return assembleRelationalVenusArchive("mdb", version, shaHex, projRows, plotRows, soilRows, vegMainRows, vegLayerRows, vegSppRows, humusRows, mineralRows), nil
}

func firstNonEmpty(m map[string]string, keys ...string) string {
	for _, k := range keys {
		if v := strings.TrimSpace(m[strings.ToLower(k)]); v != "" {
			return v
		}
	}
	return ""
}

func assembleRelationalVenusArchive(
	format, version, shaHex string,
	projRows, plotRows, soilRows, vegMainRows, vegLayerRows, vegSppRows, humusRows, mineralRows []map[string]string,
) venusNormalizedArchive {
	arch := venusNormalizedArchive{
		Format:   format,
		Version:  version,
		SHA256:   shaHex,
		Projects: map[string]string{},
	}

	projQuality := map[string]string{}
	for _, pr := range projRows {
		pid := firstNonEmpty(pr, "projectid", "id")
		pname := firstNonEmpty(pr, "projectname", "name", "projectid")
		if pid == "" {
			pid = pname
		}
		if pname == "" {
			pname = "VENUS5"
		}
		arch.Projects[pid] = pname
		projQuality[pid] = firstNonEmpty(pr, "plotquality", "siteplotquality")
	}

	soilByPlotID := map[string]map[string]string{}
	for _, sr := range soilRows {
		if pid := firstNonEmpty(sr, "plotid", "plotnumber"); pid != "" {
			soilByPlotID[pid] = sr
		}
	}
	vegMainByPlotID := map[string]map[string]string{}
	for _, vr := range vegMainRows {
		if pid := firstNonEmpty(vr, "plotid", "plotnumber"); pid != "" {
			vegMainByPlotID[pid] = vr
		}
	}

	plotIdxByKey := map[string]int{}
	for i, pr := range plotRows {
		rawPlotNum := firstNonEmpty(pr, "plotnumber", "plot")
		plotID := firstNonEmpty(pr, "plotid", "id")
		if rawPlotNum == "" {
			rawPlotNum = plotID
		}
		if rawPlotNum == "" {
			rawPlotNum = fmt.Sprintf("VP%05d", i+1)
		}
		plotNum := sqlutil.TruncateUTF16(rawPlotNum, 7)
		if plotID == "" {
			plotID = plotNum
		}

		merged := make(map[string]string, len(pr)+16)
		if sr, ok := soilByPlotID[plotID]; ok {
			for k, v := range sr {
				merged[k] = v
			}
		}
		if vm, ok := vegMainByPlotID[plotID]; ok {
			for k, v := range vm {
				merged[k] = v
			}
		}
		for k, v := range pr {
			merged[k] = v
		}

		projKey := firstNonEmpty(pr, "projectid", "projectname")
		projName := arch.Projects[projKey]
		if projName == "" {
			projName = firstNonEmpty(pr, "projectname", "projectid")
			if projName == "" {
				projName = "VENUS5"
			}
		}
		grav := isAccessTruthy(firstNonEmpty(pr, "graviti"))

		rec := venusPlotRecord{
			PlotID:      plotID,
			ProjectKey:  projKey,
			ProjectName: projName,
			PlotQuality: firstNonEmpty(merged, "siteplotquality", "plotquality"),
			PlotNumber:  plotNum,
			Graviti:     grav,
			Fields:      merged,
		}
		if rec.PlotQuality == "" {
			rec.PlotQuality = projQuality[projKey]
		}
		idx := len(arch.Plots)
		arch.Plots = append(arch.Plots, rec)
		plotIdxByKey[plotID] = idx
		if _, exists := plotIdxByKey["PN:"+rawPlotNum]; !exists {
			plotIdxByKey["PN:"+rawPlotNum] = idx
		}
		if _, exists := plotIdxByKey["PN:"+plotNum]; !exists {
			plotIdxByKey["PN:"+plotNum] = idx
		}
	}

	findPlotIdx := func(m map[string]string) (int, bool) {
		if pid := firstNonEmpty(m, "plotid"); pid != "" {
			if idx, ok := plotIdxByKey[pid]; ok {
				return idx, true
			}
		}
		if pn := firstNonEmpty(m, "plotnumber", "plot"); pn != "" {
			if idx, ok := plotIdxByKey["PN:"+pn]; ok {
				return idx, true
			}
			if idx, ok := plotIdxByKey["PN:"+sqlutil.TruncateUTF16(pn, 7)]; ok {
				return idx, true
			}
			if idx, ok := plotIdxByKey[pn]; ok {
				return idx, true
			}
		}
		return -1, false
	}

	// Map VegLayerID -> (plotIdx, layerCode)
	type layerOwner struct {
		plotIdx int
		layer   string
		height  *float64
	}
	layerMap := map[string]layerOwner{}
	for _, lr := range vegLayerRows {
		lid := firstNonEmpty(lr, "veglayerid", "layerid", "id")
		pIdx, ok := findPlotIdx(lr)
		if !ok || lid == "" {
			continue
		}
		var htPtr *float64
		if hs := firstNonEmpty(lr, "height", "layerheight"); hs != "" {
			if hv, err := strconv.ParseFloat(hs, 64); err == nil {
				htPtr = &hv
			}
		}
		layerMap[lid] = layerOwner{
			plotIdx: pIdx,
			layer:   firstNonEmpty(lr, "layer", "layercode"),
			height:  htPtr,
		}
	}

	for _, sr := range vegSppRows {
		spp := strings.ToUpper(firstNonEmpty(sr, "species", "speciescode", "code"))
		covStr := firstNonEmpty(sr, "cover", "percentcover")
		cov, err := strconv.ParseFloat(covStr, 64)
		if spp == "" || err != nil || cov == 0 {
			continue
		}
		var htPtr *float64
		if hs := firstNonEmpty(sr, "height", "speciesheight"); hs != "" {
			if hv, hErr := strconv.ParseFloat(hs, 64); hErr == nil {
				htPtr = &hv
			}
		}
		coll := firstNonEmpty(sr, "collected", "voucher")

		lid := firstNonEmpty(sr, "veglayerid", "layerid")
		if lo, ok := layerMap[lid]; ok {
			if htPtr == nil {
				htPtr = lo.height
			}
			arch.Plots[lo.plotIdx].VegObservations = append(arch.Plots[lo.plotIdx].VegObservations, venusVegObs{
				Species:   spp,
				Layer:     lo.layer,
				Cover:     cov,
				Height:    htPtr,
				Collected: coll,
			})
			continue
		}
		if pIdx, ok := findPlotIdx(sr); ok {
			arch.Plots[pIdx].VegObservations = append(arch.Plots[pIdx].VegObservations, venusVegObs{
				Species:   spp,
				Layer:     firstNonEmpty(sr, "layer", "layercode"),
				Cover:     cov,
				Height:    htPtr,
				Collected: coll,
			})
		}
	}

	for _, hr := range humusRows {
		if pIdx, ok := findPlotIdx(hr); ok {
			arch.Plots[pIdx].HumusRows = append(arch.Plots[pIdx].HumusRows, hr)
		}
	}
	for _, mr := range mineralRows {
		if pIdx, ok := findPlotIdx(mr); ok {
			arch.Plots[pIdx].MineralRows = append(arch.Plots[pIdx].MineralRows, mr)
		}
	}

	return arch
}
