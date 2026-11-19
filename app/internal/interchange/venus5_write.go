package interchange

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func writeVenusToVP08Tx(
	ctx context.Context,
	tx *sql.Tx,
	targetProject string,
	sourceProject string,
	venusVer string,
	plots []venusPlotRecord,
) (vegCount, humusCount, mineralCount int, err error) {
	envTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_Env")
	adminTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_Admin")
	vegTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_Veg")
	humusTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_Humus")
	mineralTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_Mineral")
	metaTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_Metadata")

	envCols := []string{
		"PlotNumber", "FieldNumber", "ProjectID", "Date", "SiteSurveyor", "Location",
		"FSRegionDistrict", "NtsMapSheet", "UTMZone", "UTMNorthing", "UTMEasting",
		"Latitude", "Longitude", "AirPhotoNum", "XCoord", "YCoord", "MapUnit", "PlotRepresenting",
		"Zone", "SubZone", "SiteSeries", "TransDistrib", "Ecosection", "MoistureRegime",
		"MoistureRegimeSub", "NutrientRegime", "SuccessionalStatus", "StructuralStage", "RealmClass",
		"SiteDisturbance1", "SiteDisturbance2", "Elevation", "SlopeGradient", "Aspect",
		"MesoSlopePosition", "SurfaceShape", "SurfaceTopographySize", "SurfaceTopographyType",
		"Exposure1", "Photo", "SubstrateDecWood", "SubstrateBedRock", "SubstrateRocks",
		"SubstrateMineralSoil", "SubstrateOrganicMatter", "SubstrateWater", "SiteNotes",
		"StrataCoverHerb", "StrataCoverMoss", "StrataCoverShrub", "StrataCoverTree",
		"VegSurveyor", "VegNotes", "BedrockGeology1", "BedrockGeology2", "BedrockGeology3",
		"CoarseFragLith1", "CoarseFragLith2", "CoarseFragLith3", "SoilSurveyor",
		"SoilClassGroup", "SoilClassSubGroup", "HumusForm", "HydroGeoSystem",
		"RootingDepth", "RootZoneParticleSize", "RootRestrictingDepth", "RootRestrictingType",
		"WaterSource", "SeepageDepth", "SoilDrainage", "FloodingRegimeFreq",
		"pHMethodCodeOrganic", "pHMethodCodeMineral", "SoilNotes",
		"TerrainTextureSurf", "TerrainTextureSubSurf", "SurficialMaterialSurf", "SurficialMaterialSubSurf",
		"SurfaceExpSurf", "SurfaceExpSubSurf", "GeoMorProSurf", "GeoMorProSubSurf", "SV_PercentCoarseFrags",
	}
	qEnvCols := make([]string, len(envCols))
	qEnvMarks := make([]string, len(envCols))
	for i, c := range envCols {
		qEnvCols[i] = vprocore.QuoteHeaderIdentifier(c)
		qEnvMarks[i] = "?"
	}
	envStmt, err := tx.PrepareContext(ctx, `INSERT INTO `+envTbl+` (`+strings.Join(qEnvCols, ",")+`) VALUES (`+strings.Join(qEnvMarks, ",")+`)`)
	if err != nil {
		return 0, 0, 0, err
	}
	defer envStmt.Close()

	adminStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO `+adminTbl+` ("Plot","PlotType","SitePlotQuality","UserSiteUnit","HumusThickness")
		VALUES (?,?,?,?,?)`)
	if err != nil {
		return 0, 0, 0, err
	}
	defer adminStmt.Close()

	vegColumns := []string{
		"ID", "PlotNumber", "Species", "Collected",
		"Cover1", "Height1", "Cover2", "Height2", "Cover3", "Height3", "TotalA", "HeightA",
		"Cover4", "Height4", "Cover5", "Height5", "Cover5a", "Height5a", "Cover5b", "Height5b", "Cover5c", "Height5c", "TotalB", "HeightB",
		"Cover6", "Height6", "Cover7", "Cover8", "Cover9", "Cover10",
	}
	qVegCols := make([]string, len(vegColumns))
	qVegMarks := make([]string, len(vegColumns))
	vegColPos := map[string]int{}
	for i, c := range vegColumns {
		qVegCols[i] = vprocore.QuoteHeaderIdentifier(c)
		qVegMarks[i] = "?"
		vegColPos[c] = i
	}
	vegStmt, err := tx.PrepareContext(ctx, `INSERT INTO `+vegTbl+` (`+strings.Join(qVegCols, ", ")+`) VALUES (`+strings.Join(qVegMarks, ", ")+`)`)
	if err != nil {
		return 0, 0, 0, err
	}
	defer vegStmt.Close()

	humusStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO `+humusTbl+` (
			"ID","PlotNumber","Horizon","UpperDepth","LowerDepth",
			"HumusStructureKind","HumusStructureDegree","vonPost",
			"MycelAbundance","FecalAbundance","RootsAbundance","RootsSize","HumusFormpH","Comment"
		) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
	if err != nil {
		return 0, 0, 0, err
	}
	defer humusStmt.Close()

	mineralStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO `+mineralTbl+` (
			"ID","PlotNumber","Horizon","UpperDepth","LowerDepth","Colour","ASP","Texture",
			"PercentCoarseFragsGravel","PercentCoarseFragsCobbles","PercentCoarseFragsStones",
			"PercentCoarseFragsTotal","PercentCoarseFragsShape","RootsAbundance","RootsSize",
			"MineralStructureClass","MineralStructureKind","MineralFormpH","Comments"
		) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
	if err != nil {
		return 0, 0, 0, err
	}
	defer mineralStmt.Close()

	var nextVegID, nextHumusID, nextMineralID int64 = 1, 1, 1
	seenPlots := map[string]bool{}
	nowStr := time.Now().Format("2006-01-02 15:04:05")
	projIDVal := truncateUTF16Units(sourceProject, 20)

	if err := vprocore.EnsureChildIdentityTable(ctx, tx); err != nil {
		return 0, 0, 0, err
	}
	childIDStmt, err := vprocore.PrepareChildIdentityInsertStmt(ctx, tx)
	if err != nil {
		return 0, 0, 0, err
	}
	defer childIDStmt.Close()

	quarantineSoilHorizon := func(suffix string, id int64, plotNum string, hz any, upper, lower *float64, reason string, rawRow map[string]string) error {
		qTbl := vprocore.QuoteHeaderIdentifier("__VPRO_Quarantine_" + suffix)
		srcTbl := vprocore.QuoteHeaderIdentifier(targetProject + "_" + suffix)
		if rawRow == nil {
			rawRow = map[string]string{}
		}
		payloadBytes, err := json.Marshal(rawRow)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS `+qTbl+` (
			"__QuarantinedAt" TEXT NOT NULL,
			"__Reason" TEXT NOT NULL,
			"ID" INTEGER,
			"PlotNumber" VARCHAR,
			"Horizon" VARCHAR,
			"UpperDepth" DOUBLE,
			"LowerDepth" DOUBLE,
			"PayloadJSON" TEXT NOT NULL
		)`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO `+qTbl+` ("__QuarantinedAt","__Reason","ID","PlotNumber","Horizon","UpperDepth","LowerDepth","PayloadJSON") VALUES (?,?,?,?,?,?,?,?)`,
			nowStr, reason, id, plotNum, hz, upper, lower, string(payloadBytes),
		); err != nil {
			return err
		}
		return vprocore.ReserveChildID(ctx, tx, srcTbl, id)
	}

	for _, pl := range plots {
		pNum := truncateUTF16Units(strings.TrimSpace(pl.PlotNumber), 7)
		if pNum == "" || seenPlots[pNum] {
			continue
		}
		seenPlots[pNum] = true
		f := pl.Fields

		lat := parseVenusCoordDMSOrDD(f, "latitude", "latitudedegree", "latitudeminute", "latitudesecond", false)
		lon := parseVenusCoordDMSOrDD(f, "longitude", "longitudedegree", "longitudeminute", "longitudesecond", true)

		rzps := truncateUTF16Units(firstNonEmpty(f, "rootzoneparticlesize"), 6)
		if orgTex := venusOrgSoilTexture(firstNonEmpty(f, "organicsoiltexture")); orgTex != "" && rzps == "" {
			rzps = orgTex
		}
		var rzpsAny any
		if rzps != "" {
			rzpsAny = rzps
		}

		humThick := optFltField(f, "humusthickness")
		if ht := venusHumusThickness(firstNonEmpty(f, "organichorizonthickness")); ht != nil {
			humThick = ht
		}
		svCF := optFltField(f, "sv_percentcoarsefrags")
		if cf := venusCoarseFrags(firstNonEmpty(f, "coarsefragcontent")); cf != nil {
			svCF = cf
		}

		scHerb, err := optSingleCoverField(f, pNum, "StrataCoverHerb", "stratacoverherb")
		if err != nil {
			return 0, 0, 0, err
		}
		scMoss, err := optSingleCoverField(f, pNum, "StrataCoverMoss", "stratacovermoss")
		if err != nil {
			return 0, 0, 0, err
		}
		scShrub, err := optSingleCoverField(f, pNum, "StrataCoverShrub", "stratacovershrub")
		if err != nil {
			return 0, 0, 0, err
		}
		scTree, err := optSingleCoverField(f, pNum, "StrataCoverTree", "stratacovertree")
		if err != nil {
			return 0, 0, 0, err
		}

		tTexSurf := optStrField(f, 3, "terraintexturesurf")
		if tTexSurf == nil {
			tTexSurf = combineVenusTerrain(3, f["terrainstexture1"], f["terrainstexture2"], f["terrainstexture3"])
		}
		tTexSub := optStrField(f, 3, "terraintexturesubsurf")
		if tTexSub == nil {
			tTexSub = combineVenusTerrain(3, f["terrainutexture1"], f["terrainutexture2"], f["terrainutexture3"])
		}
		sMatSurf := optStrField(f, 6, "surficialmaterialsurf")
		if sMatSurf == nil {
			sMatSurf = combineVenusTerrain(6, f["terrainsmaterial1"], f["terrainsmaterial2"], f["terrainsmaterial3"])
		}
		sMatSub := optStrField(f, 6, "surficialmaterialsubsurf")
		if sMatSub == nil {
			sMatSub = combineVenusTerrain(6, f["terrainumaterial1"], f["terrainumaterial2"], f["terrainumaterial3"])
		}
		sExpSurf := optStrField(f, 3, "surfaceexpsurf")
		if sExpSurf == nil {
			sExpSurf = combineVenusTerrain(3, f["terrainsexpression1"], f["terrainsexpression2"], f["terrainsexpression3"])
		}
		sExpSub := optStrField(f, 3, "surfaceexpsubsurf")
		if sExpSub == nil {
			sExpSub = combineVenusTerrain(3, f["terrainuexpression1"], f["terrainuexpression2"], f["terrainuexpression3"])
		}
		geoSurf := optStrField(f, 3, "geomorprosurf")
		if geoSurf == nil {
			geoSurf = combineVenusTerrain(3, f["terrainsgeo1"], f["terrainsgeo2"], f["terrainsgeo3"])
		}
		geoSub := optStrField(f, 3, "geomorprosubsurf")
		if geoSub == nil {
			geoSub = combineVenusTerrain(3, f["terrainugeo1"], f["terrainugeo2"], f["terrainugeo3"])
		}

		if _, err := envStmt.ExecContext(ctx,
			pNum,
			optStrField(f, 50, "fieldnumber", "sitenumber"),
			projIDVal,
			optStrField(f, 40, "date"),
			optStrField(f, 30, "sitesurveyor"),
			optStrField(f, 255, "location"),
			optStrField(f, 15, "fsregiondistrict", "region"),
			optStrField(f, 8, "ntsmapsheet"),
			optStrField(f, 2, "utmzone"),
			optFltField(f, "utmnorthing"),
			optFltField(f, "utmeasting"),
			lat, lon,
			optStrField(f, 20, "airphotonum"),
			optFltField(f, "xcoord"),
			optFltField(f, "ycoord"),
			optStrField(f, 15, "mapunit"),
			optStrField(f, 255, "plotrepresenting"),
			optStrField(f, 4, "zone"),
			optStrField(f, 8, "subzone"),
			optStrField(f, 5, "siteseries"),
			optStrField(f, 3, "transdistrib"),
			optStrField(f, 3, "ecosection"),
			optStrField(f, 3, "moistureregime"),
			optStrField(f, 3, "moistureregimesub"),
			optStrField(f, 2, "nutrientregime"),
			optStrField(f, 3, "successionalstatus"),
			optStrField(f, 6, "structuralstage"),
			optStrField(f, 5, "realmclass"),
			optStrField(f, 8, "sitedisturbance1"),
			optStrField(f, 8, "sitedisturbance2"),
			optIntField(f, "elevation"),
			optFltField(f, "slopegradient", "slope"),
			optIntField(f, "aspect"),
			optStrField(f, 3, "mesoslopeposition"),
			optStrField(f, 3, "surfaceshape", "surfacetopography"),
			optStrField(f, 2, "surfacetopographysize", "surfacesize"),
			optStrField(f, 3, "surfacetopographytype", "surfacetype"),
			optStrField(f, 2, "exposure1", "exposure"),
			optStrField(f, 50, "photo", "photorollnum"),
			optFltField(f, "substratedecwood"),
			optFltField(f, "substratebedrock"),
			optFltField(f, "substraterocks"),
			optFltField(f, "substratemineralsoil"),
			optFltField(f, "substrateorganicmatter"),
			optFltField(f, "substratewater"),
			optStrField(f, 0, "sitenotes"),
			scHerb,
			scMoss,
			scShrub,
			scTree,
			optStrField(f, 30, "vegsurveyor"),
			optStrField(f, 0, "vegnotes"),
			optStrField(f, 4, "bedrockgeology1", "bedrockgeology"),
			optStrField(f, 4, "bedrockgeology2"),
			optStrField(f, 4, "bedrockgeology3"),
			optStrField(f, 12, "coarsefraglith1", "coarsefraglith"),
			optStrField(f, 12, "coarsefraglith2"),
			optStrField(f, 12, "coarsefraglith3"),
			optStrField(f, 30, "soilsurveyor"),
			optStrField(f, 4, "soilclassgroup"),
			optStrField(f, 4, "soilclasssubgroup"),
			optStrField(f, 4, "humusform"),
			optStrField(f, 3, "hydrogeosystem", "hydrogeo"),
			optIntField(f, "rootingdepth"),
			rzpsAny,
			optIntField(f, "rootrestrictingdepth"),
			optStrField(f, 1, "rootrestrictingtype"),
			optStrField(f, 5, "watersource"),
			optIntField(f, "seepagedepth"),
			optStrField(f, 5, "soildrainage"),
			optStrField(f, 7, "floodingregimefreq", "floodingregime"),
			optStrField(f, 3, "phmethodcodeorganic"),
			optStrField(f, 3, "phmethodcodemineral"),
			optStrField(f, 0, "soilnotes"),
			tTexSurf, tTexSub, sMatSurf, sMatSub, sExpSurf, sExpSub, geoSurf, geoSub, svCF,
		); err != nil {
			return 0, 0, 0, fmt.Errorf("insert VENUS plot %s _Env: %w", pNum, err)
		}

		plotType := "FS882"
		if pl.Graviti {
			plotType = "1"
		}
		qualAny := nullTruncatedUTF16(pl.PlotQuality, 15)
		if _, err := adminStmt.ExecContext(ctx, pNum, plotType, qualAny, optStrField(f, 100, "usersiteunit", "assignedbecunit"), humThick); err != nil {
			return 0, 0, 0, fmt.Errorf("insert VENUS plot %s _Admin: %w", pNum, err)
		}

		// Pivot normalized VENUS VegObservations into wide VP08 _Veg
		type wideVeg struct {
			spp       string
			collected string
			covers    map[string]float64
			heights   map[string]float64
		}
		bySpp := map[string]*wideVeg{}
		var sppOrder []string
		for _, vo := range pl.VegObservations {
			code := truncateUTF16Units(strings.ToUpper(strings.TrimSpace(vo.Species)), 8)
			if code == "" || vo.Cover == 0 {
				continue
			}
			wv := bySpp[code]
			if wv == nil {
				wv = &wideVeg{spp: code, covers: map[string]float64{}, heights: map[string]float64{}}
				bySpp[code] = wv
				sppOrder = append(sppOrder, code)
			}
			if wv.collected == "" && strings.TrimSpace(vo.Collected) != "" {
				wv.collected = truncateUTF16Units(strings.TrimSpace(vo.Collected), 1)
			}
			cCol, hCol := resolveIncomingVenusLayer(vo.Layer)
			if err := accumulateImportedSingleCover(wv.covers, cCol, vo.Cover, pNum, code); err != nil {
				return 0, 0, 0, err
			}
			if vo.Height != nil && hCol != "" && *vo.Height > wv.heights[hCol] {
				wv.heights[hCol] = *vo.Height
			}
		}

		for _, code := range sppOrder {
			wv := bySpp[code]
			args := make([]any, len(vegColumns))
			args[vegColPos["ID"]] = nextVegID
			nextVegID++
			args[vegColPos["PlotNumber"]] = pNum
			args[vegColPos["Species"]] = wv.spp
			args[vegColPos["Collected"]] = nullEmpty(wv.collected)
			for cCol, cv := range wv.covers {
				if pos, ok := vegColPos[cCol]; ok {
					args[pos] = cv
				}
			}
			for hCol, hv := range wv.heights {
				if pos, ok := vegColPos[hCol]; ok {
					if hCol == "HeightB" {
						args[pos] = strconv.FormatFloat(hv, 'f', -1, 64)
					} else {
						args[pos] = hv
					}
				}
			}
			if _, err := vegStmt.ExecContext(ctx, args...); err != nil {
				return 0, 0, 0, fmt.Errorf("insert VENUS veg %s/%s: %w", pNum, wv.spp, err)
			}
			if _, err := childIDStmt.ExecContext(ctx, vegTbl, args[vegColPos["ID"]]); err != nil {
				return 0, 0, 0, err
			}
			vegCount++
		}

		for _, hr := range pl.HumusRows {
			hzAny := optStrField(hr, 8, "horizon")
			hzStr, _ := hzAny.(string)
			rawU := optFltField(hr, "depthupper", "upperdepth")
			rawL := optFltField(hr, "depthlower", "lowerdepth")
			normU, normL, qReason := normalizeLMH25HorizonDepths(hzStr, false, rawU, rawL)
			id := nextHumusID
			nextHumusID++
			if qReason != "" {
				if err := quarantineSoilHorizon("Humus", id, pNum, hzAny, rawU, rawL, qReason, hr); err != nil {
					return 0, 0, 0, err
				}
				continue
			}
			if _, err := humusStmt.ExecContext(ctx,
				id,
				pNum,
				hzAny,
				normU,
				normL,
				optStrField(hr, 5, "structurekind", "humusstructurekind"),
				optStrField(hr, 1, "structuredegree", "humusstructuredegree"),
				optIntField(hr, "vonpost"),
				optStrField(hr, 1, "mycelabundance"),
				optStrField(hr, 1, "fecalabundance"),
				optStrField(hr, 6, "rootsabundance"),
				optStrField(hr, 6, "rootssize"),
				optFltField(hr, "phorganic", "humusformph"),
				optStrField(hr, 0, "comment"),
			); err != nil {
				return 0, 0, 0, fmt.Errorf("insert VENUS humus %s: %w", pNum, err)
			}
			if _, err := childIDStmt.ExecContext(ctx, humusTbl, id); err != nil {
				return 0, 0, 0, err
			}
			humusCount++
		}

		for _, mr := range pl.MineralRows {
			hzAny := optStrField(mr, 8, "horizon")
			hzStr, _ := hzAny.(string)
			rawU := optFltField(mr, "depthupper", "upperdepth")
			rawL := optFltField(mr, "depthlower", "lowerdepth")
			normU, normL, qReason := normalizeLMH25HorizonDepths(hzStr, true, rawU, rawL)
			id := nextMineralID
			nextMineralID++
			if qReason != "" {
				if err := quarantineSoilHorizon("Mineral", id, pNum, hzAny, rawU, rawL, qReason, mr); err != nil {
					return 0, 0, 0, err
				}
				continue
			}
			if _, err := mineralStmt.ExecContext(ctx,
				id,
				pNum,
				hzAny,
				normU,
				normL,
				optStrField(mr, 14, "colour"),
				optIntField(mr, "colouraspect", "asp"),
				optStrField(mr, 4, "texture"),
				optIntField(mr, "percentcoarsefragsgravel"),
				optIntField(mr, "percentcoarsefragscobbles"),
				optIntField(mr, "percentcoarsefragsstones"),
				optIntField(mr, "percentcoarsefragstotal"),
				optStrField(mr, 1, "percentcoarsefragsshape"),
				optStrField(mr, 6, "rootsabundance"),
				optStrField(mr, 6, "rootssize"),
				optStrField(mr, 3, "structureclass", "mineralstructureclass"),
				optStrField(mr, 7, "structurekind", "mineralstructurekind"),
				optFltField(mr, "phmineral", "mineralformph"),
				optStrField(mr, 0, "comments", "comment"),
			); err != nil {
				return 0, 0, 0, fmt.Errorf("insert VENUS mineral %s: %w", pNum, err)
			}
			if _, err := childIDStmt.ExecContext(ctx, mineralTbl, id); err != nil {
				return 0, 0, 0, err
			}
			mineralCount++
		}

		pCopy := pNum
		editLabel := fmt.Sprintf("Imported VENUS ver. %s record. Project: %s", venusVer, sourceProject)
		if _, err := vprocore.RecordAudit(ctx, tx, vprocore.AuditWriteEntry{
			Project:    targetProject,
			User:       "VPro",
			PlotNumber: &pCopy,
			Table:      "_Env",
			EditField:  &editLabel,
			EditWhen:   nowStr,
		}); err != nil {
			return 0, 0, 0, fmt.Errorf("insert VENUS audit for plot %s: %w", pNum, err)
		}
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO `+metaTbl+` ("ID", "ProjectID", "ProjectTitle", "NumberOfFS882Plots", "VegCoverMethod", "Datum")
		VALUES (1, ?, ?, ?, '1', '2')`,
		projIDVal, sourceProject+" (VENUS "+venusVer+" Import)", len(seenPlots))
	return vegCount, humusCount, mineralCount, err
}

func resolveIncomingVenusLayer(layerCode string) (coverCol, heightCol string) {
	switch strings.ToUpper(strings.TrimSpace(layerCode)) {
	case "1", "A1":
		return "Cover1", "Height1"
	case "2", "A2":
		return "Cover2", "Height2"
	case "3", "A3":
		return "Cover3", "Height3"
	case "TOTALA", "A":
		return "TotalA", "HeightA"
	case "4", "B1":
		return "Cover4", "Height4"
	case "5", "B2":
		return "Cover5", "Height5"
	case "5A", "B2A":
		return "Cover5a", "Height5a"
	case "5B", "B2B":
		return "Cover5b", "Height5b"
	case "5C", "B2C":
		return "Cover5c", "Height5c"
	case "TOTALB", "B":
		return "TotalB", "HeightB"
	case "6", "C", "HERB":
		return "Cover6", "Height6"
	case "7", "D", "DH", "MOSS":
		return "Cover7", ""
	case "8", "DW":
		return "Cover8", ""
	case "9", "DR":
		return "Cover9", ""
	case "10", "EP", "EPIPHYTE":
		return "Cover10", ""
	default:
		return "Cover6", "Height6"
	}
}
