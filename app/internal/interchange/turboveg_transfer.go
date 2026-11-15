package interchange

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func extractTVDatasetFromContext(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext, lumpMap map[string]string) (tvDataset, int, error) {
	_, suByPlot, err := loadScopedPlotSiteUnits(ctx, tx, owner)
	if err != nil {
		return tvDataset{}, 0, err
	}
	sppMeta, err := loadSpeciesLookupMeta(ctx, tx)
	if err != nil {
		return tvDataset{}, 0, err
	}
	if err := enrichExportSpeciesMetaWithOldCodes(ctx, tx, sppMeta); err != nil {
		return tvDataset{}, 0, err
	}
	obs, err := extractLongVegObservations(ctx, tx, owner, suByPlot, sppMeta, lumpMap)
	if err != nil {
		return tvDataset{}, 0, err
	}

	hRows, err := tx.QueryContext(ctx, `
		SELECT
			PlotNumber,
			COALESCE(FieldNumber,''),
			COALESCE(ProjectID,''),
			COALESCE(CAST("Date" AS TEXT),''),
			Latitude,
			Longitude,
			Elevation,
			SlopeGradient,
			Aspect,
			PlotSize,
			COALESCE("Zone",''),
			COALESCE(SubZone,''),
			COALESCE(SiteSeries,''),
			COALESCE(MoistureRegime,''),
			COALESCE(NutrientRegime,''),
			COALESCE(MesoSlopePosition,''),
			COALESCE(SurfaceShape,''),
			COALESCE(SoilDrainage,''),
			COALESCE(HumusForm,''),
			COALESCE(SiteSurveyor,''),
			COALESCE(Location,''),
			COALESCE(SiteNotes,''),
			COALESCE(VegNotes,''),
			COALESCE(SoilNotes,'')
		FROM USysEnv
		ORDER BY PlotNumber`)
	if err != nil {
		return tvDataset{}, 0, fmt.Errorf("read USysEnv for TurboVeg export: %w", err)
	}
	defer hRows.Close()

	var headers []tvPlotHeader
	plotIdxByNum := map[string]int{}
	for hRows.Next() {
		var h tvPlotHeader
		var lat, lon, slope, pSize sql.NullFloat64
		var elev, aspect sql.NullInt64
		if err := hRows.Scan(
			&h.PlotNumber, &h.FieldNumber, &h.ProjectID, &h.Date,
			&lat, &lon, &elev, &slope, &aspect, &pSize,
			&h.Zone, &h.SubZone, &h.SiteSeries, &h.MoistureRegime, &h.NutrientRegime,
			&h.MesoSlopePosition, &h.SurfaceShape, &h.SoilDrainage, &h.HumusForm,
			&h.Surveyor, &h.Location, &h.SiteNotes, &h.VegNotes, &h.SoilNotes,
		); err != nil {
			return tvDataset{}, 0, err
		}
		if lat.Valid {
			v := lat.Float64
			h.Latitude = &v
		}
		if lon.Valid {
			v := lon.Float64
			h.Longitude = &v
		}
		if elev.Valid {
			v := int(elev.Int64)
			h.Elevation = &v
		}
		if slope.Valid {
			v := slope.Float64
			h.Slope = &v
		}
		if aspect.Valid {
			v := int(aspect.Int64)
			h.Aspect = &v
		}
		if pSize.Valid {
			v := pSize.Float64
			h.PlotSize = &v
		}
		h.SiteUnit = suByPlot[h.PlotNumber]
		h.PlotID = len(headers) + 1
		h.GUID = newTurboVegUUID()
		plotIdxByNum[h.PlotNumber] = len(headers)
		headers = append(headers, h)
	}
	if err := hRows.Err(); err != nil {
		return tvDataset{}, 0, err
	}

	distinctCodes := map[string]struct{}{}
	for _, o := range obs {
		distinctCodes[o.Species] = struct{}{}
	}
	sortedCodes := make([]string, 0, len(distinctCodes))
	for c := range distinctCodes {
		sortedCodes = append(sortedCodes, c)
	}
	slices.Sort(sortedCodes)

	sppNRByCode := make(map[string]int, len(sortedCodes))
	sppDefs := make([]tvSpeciesItem, len(sortedCodes))
	for i, code := range sortedCodes {
		nr := i + 1
		sppNRByCode[code] = nr
		m := sppMeta[code]
		sci := strings.TrimSpace(m.ScientificName)
		if sci == "" {
			sci = code
		}
		sppDefs[i] = tvSpeciesItem{
			SpeciesNR:      nr,
			SpeciesCode:    code,
			LetterCode:     truncateUTF16Units(code, 7),
			ScientificName: sci,
			EnglishName:    m.EnglishName,
			Lifeform:       m.Lifeform,
			Authority:      m.Authority,
		}
	}

	bundles := make([]tvExportPlot, len(headers))
	for i, h := range headers {
		bundles[i] = tvExportPlot{Header: h}
	}

	totalObs := 0
	for _, o := range obs {
		pIdx, ok := plotIdxByNum[o.PlotNumber]
		if !ok {
			continue
		}
		cw, ok := vproSublayerCodeToTV[o.Layer]
		tvLayerID := 6
		vproLayer := o.Layer
		if ok {
			tvLayerID = cw.TVLayerID
			vproLayer = cw.VProLayer
		}
		cov := o.Cover
		if float32(cov) >= 100 {
			cov = 99.99
		}
		sci := strings.TrimSpace(o.ScientificName)
		if sci == "" {
			sci = sppMeta[o.Species].ScientificName
		}
		if sci == "" {
			sci = o.Species
		}
		bundles[pIdx].Observations = append(bundles[pIdx].Observations, tvExportObs{
			SpeciesNR:   sppNRByCode[o.Species],
			SpeciesCode: o.Species,
			SciName:     sci,
			TVLayerID:   tvLayerID,
			VProLayer:   vproLayer,
			Cover:       cov,
			Height:      o.Height,
			Collected:   o.Collected,
		})
		totalObs++
	}

	projName := strings.TrimSpace(owner.Selection.Project)
	if projName == "" {
		projName = "VProExport"
	}

	return tvDataset{
		ProjectName: projName,
		Species:     sppDefs,
		Plots:       bundles,
	}, totalObs, nil
}

func ExportTurboVeg(s *vprocore.ContextService, ctx context.Context, contextID string, request TurboVegExportRequest) (TurboVegExportOutcome, error) {
	if strings.TrimSpace(request.DestinationPath) == "" {
		return TurboVegExportOutcome{}, errors.New("TurboVeg export requires a non-empty destinationPath")
	}
	format := strings.ToLower(strings.TrimSpace(request.Format))
	if format == "" {
		if strings.HasSuffix(strings.ToLower(request.DestinationPath), ".xml") {
			format = TurboVegFormatXML
		} else {
			format = TurboVegFormatSQLite
		}
	}
	if format != TurboVegFormatXML && format != TurboVegFormatSQLite {
		return TurboVegExportOutcome{}, fmt.Errorf("unsupported TurboVeg export format %q (expected xml or sqlite)", request.Format)
	}

	dest := strings.TrimSpace(request.DestinationPath)
	if format == TurboVegFormatXML && !strings.HasSuffix(strings.ToLower(dest), ".xml") {
		dest += ".xml"
	} else if format == TurboVegFormatSQLite && !strings.HasSuffix(strings.ToLower(dest), ".sqlite") && !strings.HasSuffix(strings.ToLower(dest), ".db") {
		dest += ".sqlite"
	}

	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (TurboVegExportOutcome, error) {
		owner := plots.Projects.Sqlite
		lumpMap, err := loadOptionalLumpMap(ctx, owner.Selection.ProjectPath, request.LumpTable, request.LumpDBPath)
		if err != nil {
			return TurboVegExportOutcome{}, err
		}

		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return TurboVegExportOutcome{}, err
		}
		defer owner.Mu.Unlock()
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return TurboVegExportOutcome{}, err
		}
		defer func() { _ = tx.Rollback() }()

		ds, obsCount, err := extractTVDatasetFromContext(ctx, tx, owner, lumpMap)
		if err != nil {
			return TurboVegExportOutcome{}, err
		}
		if err := tx.Commit(); err != nil {
			return TurboVegExportOutcome{}, err
		}

		var writtenPath, shaHex string
		if format == TurboVegFormatXML {
			xmlBytes, encErr := encodeTurboVegXML(ctx, ds)
			if encErr != nil {
				return TurboVegExportOutcome{}, encErr
			}
			writtenPath, shaHex, err = writeAtomicExportFile(dest, xmlBytes)
			if err != nil {
				return TurboVegExportOutcome{}, err
			}
		} else {
			writtenPath, shaHex, err = writeTurboVeg3SQLite(ctx, dest, ds)
			if err != nil {
				return TurboVegExportOutcome{}, err
			}
		}

		return TurboVegExportOutcome{
			Format:           format,
			Path:             writtenPath,
			SHA256:           shaHex,
			PlotCount:        len(ds.Plots),
			SpeciesCount:     len(ds.Species),
			ObservationCount: obsCount,
		}, nil
	})
}

func loadActiveContextSpeciesResolver(s *vprocore.ContextService, ctx context.Context, contextID string) (*speciesImportResolver, error) {
	if s == nil {
		return nil, nil
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (*speciesImportResolver, error) {
		owner := plots.Projects.Sqlite
		if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
			return nil, err
		}
		defer owner.Mu.Unlock()
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() { _ = tx.Rollback() }()
		res, err := loadSpeciesImportResolver(ctx, tx)
		if err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return res, nil
	})
}

func ImportTurboVeg(s *vprocore.ContextService, ctx context.Context, contextID string, request TurboVegImportRequest) (TurboVegImportOutcome, error) {
	src := strings.TrimSpace(request.SourcePath)
	if src == "" || !utf8.ValidString(src) || strings.ContainsRune(src, 0) {
		return TurboVegImportOutcome{}, errors.New("TurboVeg import requires a valid sourcePath")
	}
	absSrc, err := filepath.Abs(filepath.Clean(src))
	if err != nil {
		return TurboVegImportOutcome{}, err
	}
	format := strings.ToLower(strings.TrimSpace(request.Format))
	if format == "" {
		if strings.EqualFold(filepath.Ext(absSrc), ".xml") {
			format = TurboVegFormatXML
		} else {
			format = TurboVegFormatSQLite
		}
	}
	if format != TurboVegFormatXML && format != TurboVegFormatSQLite {
		return TurboVegImportOutcome{}, fmt.Errorf("unsupported TurboVeg import format %q", format)
	}

	resolver, err := loadActiveContextSpeciesResolver(s, ctx, contextID)
	if err != nil {
		return TurboVegImportOutcome{}, err
	}
	resolver.resolveVProCodeSynonyms = request.ResolveVProCodeSynonyms

	var plots []tvImportPlot
	switch format {
	case TurboVegFormatXML:
		plots, err = parseTurboVegXMLFile(ctx, absSrc, resolver)
	case TurboVegFormatSQLite:
		plots, err = readTurboVeg3SQLiteFile(ctx, absSrc, resolver)
	}
	if err != nil {
		return TurboVegImportOutcome{}, err
	}
	if len(plots) == 0 {
		return TurboVegImportOutcome{}, errors.New("TurboVeg source contains zero plots")
	}

	var persistedSppCount, persistedObsCount int
	destPath, destSHA, activated, newState, err := stageAndPublishVP08Project(
		s, ctx, contextID, request.TargetProject, request.DestinationPath, request.ActivateOnSuccess,
		func(ctx context.Context, tx *sql.Tx, project string) error {
			var pErr error
			persistedSppCount, persistedObsCount, pErr = populateVP08FromTVPlots(ctx, tx, project, plots)
			return pErr
		},
	)
	if err != nil {
		return TurboVegImportOutcome{}, err
	}

	return TurboVegImportOutcome{
		SourcePath:       absSrc,
		Format:           format,
		TargetProject:    strings.TrimSpace(request.TargetProject),
		DestinationPath:  destPath,
		DestinationSHA:   destSHA,
		PlotCount:        len(plots),
		SpeciesCount:     persistedSppCount,
		ObservationCount: persistedObsCount,
		Activated:        activated,
		State:            newState,
	}, nil
}

func abbreviateSpeciesName(sci string) string {
	parts := strings.Fields(strings.ToUpper(sci))
	if len(parts) == 0 {
		return ""
	}
	if len(parts) == 1 {
		return truncateUTF16Units(parts[0], 8)
	}
	g := truncateUTF16Units(parts[0], 4)
	sp := truncateUTF16Units(parts[1], 3)
	return truncateUTF16Units(g+sp, 8)
}

func populateVP08FromTVPlots(ctx context.Context, tx *sql.Tx, project string, plots []tvImportPlot) (int, int, error) {
	envTbl := vprocore.QuoteHeaderIdentifier(project + "_Env")
	adminTbl := vprocore.QuoteHeaderIdentifier(project + "_Admin")
	vegTbl := vprocore.QuoteHeaderIdentifier(project + "_Veg")
	metaTbl := vprocore.QuoteHeaderIdentifier(project + "_Metadata")
	auditTbl := vprocore.QuoteHeaderIdentifier(project + "_Audit")

	envStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO `+envTbl+` (
			"PlotNumber","FieldNumber","ProjectID","Date","Latitude","Longitude",
			"Elevation","SlopeGradient","Aspect","Zone","SubZone","SiteSeries",
			"MoistureRegime","NutrientRegime","MesoSlopePosition","SurfaceShape",
			"SoilDrainage","HumusForm","SiteSurveyor","Location","SiteNotes","VegNotes","SoilNotes"
		) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
	if err != nil {
		return 0, 0, err
	}
	defer envStmt.Close()

	adminStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO `+adminTbl+` ("Plot","PlotType","PlotSize","UserSiteUnit") VALUES (?,?,?,?)`)
	if err != nil {
		return 0, 0, err
	}
	defer adminStmt.Close()

	vegColumns := []string{
		"ID", "PlotNumber", "Species", "Collected",
		"Cover1", "Height1", "Cover2", "Height2", "Cover3", "Height3", "TotalA", "HeightA",
		"Cover4", "Height4", "Cover5", "Height5", "Cover5a", "Height5a", "Cover5b", "Height5b", "Cover5c", "Height5c", "TotalB", "HeightB",
		"Cover6", "Height6", "Cover7", "Cover8", "Cover9", "Cover10",
	}
	qVegCols := make([]string, len(vegColumns))
	qMarks := make([]string, len(vegColumns))
	colPos := map[string]int{}
	for i, c := range vegColumns {
		qVegCols[i] = vprocore.QuoteHeaderIdentifier(c)
		qMarks[i] = "?"
		colPos[c] = i
	}
	vegStmt, err := tx.PrepareContext(ctx, `INSERT INTO `+vegTbl+` (`+strings.Join(qVegCols, ", ")+`) VALUES (`+strings.Join(qMarks, ", ")+`)`)
	if err != nil {
		return 0, 0, err
	}
	defer vegStmt.Close()

	var nextVegID int64 = 1
	suRows := [][2]string{}
	seenRawPlots := map[string]bool{}
	reservedLiteralShort := map[string]bool{}
	for _, pb := range plots {
		rawPlot := strings.TrimSpace(pb.Header.PlotNumber)
		if rawPlot == "" {
			return 0, 0, fmt.Errorf("TurboVeg plot %d has an empty plot number", pb.Header.PlotID)
		}
		if seenRawPlots[rawPlot] {
			return 0, 0, fmt.Errorf("duplicate TurboVeg source plot number %q", rawPlot)
		}
		seenRawPlots[rawPlot] = true
		if len(utf16.Encode([]rune(rawPlot))) <= 7 {
			reservedLiteralShort[rawPlot] = true
		}
	}

	usedTargetPlots := map[string]bool{}
	persistedSpecies := map[string]struct{}{}
	persistedObsCount := 0
	nowStr := time.Now().Format("2006-01-02 15:04:05")

	for plotIdx, pb := range plots {
		if plotIdx%128 == 0 {
			if err := ctx.Err(); err != nil {
				return 0, 0, err
			}
		}
		h := pb.Header
		rawPlot := strings.TrimSpace(h.PlotNumber)
		for _, tf := range [][2]string{
			{"PlotNumber", h.PlotNumber},
			{"FieldNumber", h.FieldNumber},
			{"ProjectID", h.ProjectID},
			{"Date", h.Date},
			{"Zone", h.Zone},
			{"SubZone", h.SubZone},
			{"SiteSeries", h.SiteSeries},
			{"SiteUnit", h.SiteUnit},
			{"MoistureRegime", h.MoistureRegime},
			{"NutrientRegime", h.NutrientRegime},
			{"MesoSlopePosition", h.MesoSlopePosition},
			{"SurfaceShape", h.SurfaceShape},
			{"SoilDrainage", h.SoilDrainage},
			{"HumusForm", h.HumusForm},
			{"Surveyor", h.Surveyor},
			{"Location", h.Location},
			{"SiteNotes", h.SiteNotes},
			{"VegNotes", h.VegNotes},
			{"SoilNotes", h.SoilNotes},
		} {
			if err := validateUTF8Text(tf[1], tf[0]); err != nil {
				return 0, 0, err
			}
		}
		var slopeSingle *float64
		if h.Slope != nil {
			sv, err := validateFiniteSingleFloat(*h.Slope, "SlopeGradient", true)
			if err != nil {
				return 0, 0, fmt.Errorf("plot %s: %w", rawPlot, err)
			}
			slopeSingle = &sv
		}
		pNum := allocateUniqueTVPlotNumber(rawPlot, usedTargetPlots, reservedLiteralShort)
		usedTargetPlots[pNum] = true

		projID := h.ProjectID
		if strings.TrimSpace(projID) == "" {
			projID = project
		}
		projID = truncateUTF16Units(projID, 20)

		if _, err := envStmt.ExecContext(ctx,
			pNum,
			nullTruncatedUTF16(h.FieldNumber, 50),
			projID,
			nullTruncatedUTF16(h.Date, 40),
			h.Latitude, h.Longitude,
			h.Elevation, slopeSingle, h.Aspect,
			nullTruncatedUTF16(h.Zone, 4),
			nullTruncatedUTF16(h.SubZone, 8),
			nullTruncatedUTF16(h.SiteSeries, 5),
			nullTruncatedUTF16(h.MoistureRegime, 3),
			nullTruncatedUTF16(h.NutrientRegime, 2),
			nullTruncatedUTF16(h.MesoSlopePosition, 3),
			nullTruncatedUTF16(h.SurfaceShape, 3),
			nullTruncatedUTF16(h.SoilDrainage, 5),
			nullTruncatedUTF16(h.HumusForm, 4),
			nullTruncatedUTF16(h.Surveyor, 30),
			nullTruncatedUTF16(h.Location, 255),
			nullEmpty(h.SiteNotes), nullEmpty(h.VegNotes), nullEmpty(h.SoilNotes),
		); err != nil {
			return 0, 0, fmt.Errorf("insert plot %s into _Env: %w", pNum, err)
		}
		if _, err := adminStmt.ExecContext(ctx, pNum, "FS882", h.PlotSize, nullTruncatedUTF16(h.SiteUnit, 100)); err != nil {
			return 0, 0, fmt.Errorf("insert plot %s into _Admin: %w", pNum, err)
		}
		if suUnit := truncateUTF16Units(strings.TrimSpace(h.SiteUnit), 255); suUnit != "" {
			suRows = append(suRows, [2]string{pNum, suUnit})
		}

		type wideRow struct {
			spp       string
			collected string
			covers    map[string]float64
			heights   map[string]float64
		}
		bySpp := map[string]*wideRow{}
		var sppOrder []string
		for _, o := range pb.Observations {
			if err := validateUTF8Text(o.SpeciesCode, "Species"); err != nil {
				return 0, 0, err
			}
			if err := validateUTF8Text(o.Collected, "Collected"); err != nil {
				return 0, 0, err
			}
			code := truncateUTF16Units(strings.ToUpper(strings.TrimSpace(o.SpeciesCode)), 8)
			if code == "" {
				continue
			}
			wr := bySpp[code]
			if wr == nil {
				wr = &wideRow{spp: code, covers: map[string]float64{}, heights: map[string]float64{}}
				bySpp[code] = wr
				sppOrder = append(sppOrder, code)
			}
			if wr.collected == "" && strings.TrimSpace(o.Collected) != "" {
				wr.collected = truncateUTF16Units(strings.TrimSpace(o.Collected), 1)
			}
			cCol, hCol := resolveIncomingTurboVegLayer(o.TVLayerRaw, o.VProLayer, o.IsWoody)
			if err := accumulateImportedSingleCover(wr.covers, cCol, o.Cover, pNum, code); err != nil {
				return 0, 0, err
			}
			if o.Height != nil && hCol != "" {
				hv, err := validateFiniteSingleFloat(*o.Height, hCol, true)
				if err != nil {
					return 0, 0, fmt.Errorf("plot %s species %s: %w", pNum, code, err)
				}
				if hv > wr.heights[hCol] {
					wr.heights[hCol] = hv
				}
			}
			persistedSpecies[code] = struct{}{}
			persistedObsCount++
		}

		for _, code := range sppOrder {
			wr := bySpp[code]
			args := make([]any, len(vegColumns))
			args[colPos["ID"]] = nextVegID
			nextVegID++
			args[colPos["PlotNumber"]] = pNum
			args[colPos["Species"]] = wr.spp
			args[colPos["Collected"]] = nullEmpty(wr.collected)
			for cCol, cv := range wr.covers {
				if pos, ok := colPos[cCol]; ok {
					args[pos] = cv
				}
			}
			for hCol, hv := range wr.heights {
				if pos, ok := colPos[hCol]; ok {
					if hCol == "HeightB" {
						args[pos] = strconv.FormatFloat(hv, 'f', -1, 64)
					} else {
						args[pos] = hv
					}
				}
			}
			if _, err := vegStmt.ExecContext(ctx, args...); err != nil {
				return 0, 0, fmt.Errorf("insert veg %s/%s: %w", pNum, wr.spp, err)
			}
		}

		if _, err := tx.ExecContext(ctx, `
			INSERT INTO `+auditTbl+` ("Project","User","PlotNumber","Table","EditField","EditWhen","Restore","Flag")
			VALUES (?, 'VPro', ?, 'Environment', 'Imported TurboVeg record', ?, 0, 0)`,
			project, pNum, nowStr); err != nil {
			return 0, 0, fmt.Errorf("insert audit for plot %s: %w", pNum, err)
		}
	}

	if len(suRows) > 0 {
		suTbl := vprocore.QuoteHeaderIdentifier(project + "_SU")
		if _, err := tx.ExecContext(ctx, `
			CREATE TABLE `+suTbl+` ("PlotNumber" VARCHAR, "SiteUnit" VARCHAR);
			CREATE UNIQUE INDEX `+vprocore.QuoteHeaderIdentifier("uidx_"+project+"_SU_PlotNumber")+` ON `+suTbl+`("PlotNumber");
			CREATE INDEX `+vprocore.QuoteHeaderIdentifier("idx_"+project+"_SU_SiteUnit")+` ON `+suTbl+`("SiteUnit");
			INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP04');`, project+"_SU"); err != nil {
			return 0, 0, err
		}
		for _, pair := range suRows {
			if _, err := tx.ExecContext(ctx, `INSERT INTO `+suTbl+` ("PlotNumber", "SiteUnit") VALUES (?, ?)`, pair[0], pair[1]); err != nil {
				return 0, 0, err
			}
		}
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO `+metaTbl+` ("ID", "ProjectID", "ProjectTitle", "NumberOfFS882Plots", "VegCoverMethod", "Datum")
		VALUES (1, ?, ?, ?, '1', '2')`,
		project, project+" (TurboVeg Import)", len(usedTargetPlots))
	return len(persistedSpecies), persistedObsCount, err
}

func allocateUniqueTVPlotNumber(rawPlot string, usedTargetPlots, reservedLiteralShort map[string]bool) string {
	cand := truncateUTF16Units(rawPlot, 7)
	if cand != "" && !usedTargetPlots[cand] && (cand == rawPlot || !reservedLiteralShort[cand]) {
		return cand
	}
	for seq := 1; ; seq++ {
		suffix := "~" + strconv.Itoa(seq)
		var disambig string
		if maxPrefix := 7 - len(suffix); maxPrefix > 0 {
			disambig = truncateUTF16Units(rawPlot, maxPrefix) + suffix
		} else {
			b36 := strings.ToUpper(strconv.FormatInt(int64(seq), 36))
			if len(b36) < 7 {
				b36 = strings.Repeat("0", 7-len(b36)) + b36
			}
			disambig = truncateUTF16Units(b36, 7)
		}
		if disambig != "" && !usedTargetPlots[disambig] && !reservedLiteralShort[disambig] {
			return disambig
		}
	}
}
