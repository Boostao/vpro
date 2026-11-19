package classification

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// BECdb v13 & MasterSiteUnitList mask pattern (evaluated after stripping BGC spacing), e.g. CWHvm1/01, CWHvh3/Wf51, BWBSmw/102$6B.1.
var becUnitMaskPattern = regexp.MustCompile(`^[A-Z]{2,4}[a-z]{1,3}[0-9a-z]{0,3}/[A-Za-z0-9.\-$()]{1,14}$`)

func compactBECUnitCode(code string) string {
	var b strings.Builder
	b.Grow(len(code))
	for _, r := range code {
		if !unicode.IsSpace(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

type SUPlotLeaf struct {
	PlotNumber     string `json:"plotNumber"`
	FieldNumber    string `json:"fieldNumber"`
	Zone           string `json:"zone"`
	SubZone        string `json:"subZone"`
	SiteSeries     string `json:"siteSeries"`
	UserSiteUnit   string `json:"userSiteUnit"`
	MoistureRegime string `json:"moistureRegime"`
	NutrientRegime string `json:"nutrientRegime"`
	Elevation      *int64 `json:"elevation"`
	SiteUnit       string `json:"siteUnit"`
	PresentInSU    bool   `json:"presentInSu"`
	InProjectEnv   bool   `json:"inProjectEnv"`
	Locked         bool   `json:"locked"`
}

type SUUnitBucket struct {
	SiteUnit  string       `json:"siteUnit"`
	LongName  string       `json:"longName"`
	Origin    string       `json:"origin"` // "master" | "user" | ""
	MaskValid bool         `json:"maskValid"`
	PlotCount int          `json:"plotCount"`
	Plots     []SUPlotLeaf `json:"plots"`
}

type SUPlotTree struct {
	ContextID       string         `json:"contextId"`
	Project         string         `json:"project"`
	ProjectPath     string         `json:"projectPath"`
	SU              string         `json:"su"`
	SUPath          string         `json:"suPath"`
	Units           []SUUnitBucket `json:"units"`
	UnassignedPlots []SUPlotLeaf   `json:"unassignedPlots"`
	OrphanPlots     []SUPlotLeaf   `json:"orphanPlots"`
	TotalProject    int            `json:"totalProject"`
	TotalAssigned   int            `json:"totalAssigned"`
	TotalUnassigned int            `json:"totalUnassigned"`
}

type PlotInspectorSpecies struct {
	Species        string  `json:"species"`
	ScientificName string  `json:"scientificName"`
	EnglishName    string  `json:"englishName"`
	CoverA         string  `json:"coverA"`
	CoverB         string  `json:"coverB"`
	CoverC         string  `json:"coverC"`
	CoverD         string  `json:"coverD"`
	TotalCover     float64 `json:"totalCover"`
	TotalFormatted string  `json:"totalFormatted"`
}

type PlotInspectorSummary struct {
	ContextID      string                 `json:"contextId"`
	PlotNumber     string                 `json:"plotNumber"`
	FieldNumber    string                 `json:"fieldNumber"`
	ProjectID      string                 `json:"projectId"`
	Zone           string                 `json:"zone"`
	SubZone        string                 `json:"subZone"`
	SiteSeries     string                 `json:"siteSeries"`
	UserSiteUnit   string                 `json:"userSiteUnit"`
	BECSiteUnit    string                 `json:"becSiteUnit"`
	CurrentSUUnit  string                 `json:"currentSuUnit"`
	MoistureRegime string                 `json:"moistureRegime"`
	NutrientRegime string                 `json:"nutrientRegime"`
	Elevation      *int64                 `json:"elevation"`
	Slope          string                 `json:"slope"`
	Aspect         *int64                 `json:"aspect"`
	Latitude       *float64               `json:"latitude"`
	Longitude      *float64               `json:"longitude"`
	TopSpecies     []PlotInspectorSpecies `json:"topSpecies"`
}

func BECUnitMaskValid(code string) bool {
	return becUnitMaskPattern.MatchString(compactBECUnitCode(code))
}

func GetSUPlotTree(ctx context.Context, contexts *vprocore.ContextService, contextID, filterText string) (*SUPlotTree, error) {
	if ctx == nil {
		return nil, errors.New("SU plot tree requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	if !utf8.ValidString(filterText) || strings.ContainsRune(filterText, 0) {
		return nil, errors.New("filter text must be valid UTF-8 without NUL")
	}
	needle := strings.ToLower(strings.TrimSpace(filterText))

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ *SUPlotTree, resultErr error) {
		owner := plots.Projects.Sqlite
		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return nil, err
		}
		defer unlock()
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}()

		project := owner.Selection.Project
		adminUserUnits := map[string]string{}
		adminRows, err := tx.QueryContext(ctx,
			`SELECT CAST("Plot" AS BLOB), COALESCE(CAST("UserSiteUnit" AS TEXT), '')
			 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Admin")+`
			 WHERE typeof("Plot")='text'`)
		if err != nil {
			return nil, err
		}
		for adminRows.Next() {
			var rawPlot []byte
			var userUnit string
			if err := adminRows.Scan(&rawPlot, &userUnit); err != nil {
				adminRows.Close()
				return nil, err
			}
			key := string(rawPlot)
			if _, exists := adminUserUnits[key]; !exists {
				adminUserUnits[key] = userUnit
			}
		}
		if err := errors.Join(adminRows.Err(), adminRows.Close()); err != nil {
			return nil, err
		}

		envMap := map[string]SUPlotLeaf{}
		envOrder := []string{}

		envRows, err := tx.QueryContext(ctx,
			`SELECT typeof(env."PlotNumber"),
			        CAST(env."PlotNumber" AS BLOB),
			        CAST(env."PlotNumber" AS TEXT),
			        COALESCE(CAST(env."FieldNumber" AS TEXT), ''),
			        COALESCE(CAST(env."Zone" AS TEXT), ''),
			        COALESCE(CAST(env."SubZone" AS TEXT), ''),
			        COALESCE(CAST(env."SiteSeries" AS TEXT), ''),
			        COALESCE(CAST(env."MoistureRegime" AS TEXT), ''),
			        COALESCE(CAST(env."NutrientRegime" AS TEXT), ''),
			        env."Elevation",
			        COALESCE(CAST(env."Flag" AS INTEGER), 0)
			 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Env")+` AS env
			 WHERE env."PlotNumber" IS NOT NULL
			 ORDER BY env."PlotNumber" COLLATE NOCASE ASC, env.rowid ASC`)
		if err != nil {
			return nil, err
		}
		for envRows.Next() {
			var plotType string
			var rawPlot []byte
			var leaf SUPlotLeaf
			var elev sql.NullInt64
			var flagInt int64
			if err := envRows.Scan(
				&plotType, &rawPlot, &leaf.PlotNumber, &leaf.FieldNumber, &leaf.Zone, &leaf.SubZone, &leaf.SiteSeries,
				&leaf.MoistureRegime, &leaf.NutrientRegime, &elev, &flagInt,
			); err != nil {
				envRows.Close()
				return nil, err
			}
			if elev.Valid {
				v := elev.Int64
				leaf.Elevation = &v
			}
			leaf.InProjectEnv = true
			leaf.Locked = flagInt != 0
			typedKey := plotType + ":" + leaf.PlotNumber
			if plotType == "text" {
				rawKey := string(rawPlot)
				typedKey = "text:" + rawKey
				leaf.UserSiteUnit = adminUserUnits[rawKey]
			}
			if _, exists := envMap[typedKey]; !exists {
				envOrder = append(envOrder, typedKey)
			}
			envMap[typedKey] = leaf
		}
		if err := errors.Join(envRows.Err(), envRows.Close()); err != nil {
			return nil, err
		}

		// Load unit long names from MasterSiteUnitList & UserSiteUnitList
		type unitCatalogMeta struct {
			longName string
			origin   string
		}
		unitNames := map[string]unitCatalogMeta{}
		for _, src := range []struct {
			role, table, origin string
		}{
			{"VLists", "MasterSiteUnitList", "master"},
			{"VUser", "UserSiteUnitList", "user"},
		} {
			uRows, uErr := tx.QueryContext(ctx,
				`SELECT COALESCE(CAST("SiteSeries" AS TEXT), ''), COALESCE(CAST("SiteSeriesLongName" AS TEXT), '')
				 FROM `+vprocore.QuoteHeaderIdentifier(src.role)+`.`+vprocore.QuoteHeaderIdentifier(src.table))
			if uErr == nil {
				for uRows.Next() {
					var code, lname string
					if err := uRows.Scan(&code, &lname); err == nil && strings.TrimSpace(code) != "" {
						trimmed := strings.TrimSpace(code)
						meta := unitCatalogMeta{longName: lname, origin: src.origin}
						unitNames[trimmed] = meta
						if compact := compactBECUnitCode(trimmed); compact != "" {
							if _, exists := unitNames[compact]; !exists {
								unitNames[compact] = meta
							}
						}
					}
				}
				uRows.Close()
			}
		}

		tree := &SUPlotTree{
			ContextID:       contextID,
			Project:         project,
			ProjectPath:     owner.Selection.ProjectPath,
			SU:              owner.Selection.SU,
			SUPath:          owner.Selection.SUPath,
			Units:           []SUUnitBucket{},
			UnassignedPlots: []SUPlotLeaf{},
			OrphanPlots:     []SUPlotLeaf{},
			TotalProject:    len(envOrder),
		}

		matchesFilter := func(leaf SUPlotLeaf, unitLongName string) bool {
			if needle == "" {
				return true
			}
			hay := strings.ToLower(strings.Join([]string{
				leaf.PlotNumber, leaf.FieldNumber, leaf.SiteUnit, unitLongName,
				leaf.Zone, leaf.SubZone, leaf.SiteSeries, leaf.UserSiteUnit,
			}, " "))
			return strings.Contains(hay, needle)
		}

		if owner.Selection.SU == "None" || owner.Selection.SU == "" {
			for _, plotNum := range envOrder {
				leaf := envMap[plotNum]
				tree.TotalUnassigned++
				if matchesFilter(leaf, "") {
					tree.UnassignedPlots = append(tree.UnassignedPlots, leaf)
				}
			}
		} else {
			suTable := owner.Selection.SU + "_SU"
			suRows, sErr := tx.QueryContext(ctx,
				`SELECT typeof("PlotNumber"), CAST("PlotNumber" AS BLOB), CAST("PlotNumber" AS TEXT), CAST("SiteUnit" AS TEXT)
				 FROM "su".`+vprocore.QuoteHeaderIdentifier(suTable)+` ORDER BY rowid ASC`)
			if sErr != nil {
				return nil, sErr
			}
			seenSUPlot := map[string]bool{}
			bucketMap := map[string]*SUUnitBucket{}

			for suRows.Next() {
				var plotType string
				var rawPlot []byte
				var p, u sql.NullString
				if err := suRows.Scan(&plotType, &rawPlot, &p, &u); err != nil {
					suRows.Close()
					return nil, err
				}
				if plotType == "null" || !p.Valid || strings.TrimSpace(p.String) == "" {
					continue
				}
				plotNum := p.String
				unitCode := ""
				if u.Valid {
					unitCode = strings.TrimSpace(u.String)
				}
				if plotType != "text" {
					orphan := SUPlotLeaf{
						PlotNumber:   plotNum,
						SiteUnit:     unitCode,
						PresentInSU:  true,
						InProjectEnv: false,
					}
					if matchesFilter(orphan, unitNames[unitCode].longName) {
						tree.OrphanPlots = append(tree.OrphanPlots, orphan)
					}
					continue
				}
				typedKey := "text:" + string(rawPlot)
				seenSUPlot[typedKey] = true
				baseLeaf, inEnv := envMap[typedKey]
				if !inEnv {
					orphan := SUPlotLeaf{
						PlotNumber:   plotNum,
						SiteUnit:     unitCode,
						PresentInSU:  true,
						InProjectEnv: false,
					}
					if matchesFilter(orphan, unitNames[unitCode].longName) {
						tree.OrphanPlots = append(tree.OrphanPlots, orphan)
					}
					continue
				}
				baseLeaf.PresentInSU = true
				baseLeaf.SiteUnit = unitCode

				if unitCode == "" {
					tree.TotalUnassigned++
					if matchesFilter(baseLeaf, "") {
						tree.UnassignedPlots = append(tree.UnassignedPlots, baseLeaf)
					}
					continue
				}

				tree.TotalAssigned++
				meta, ok := unitNames[unitCode]
				if !ok {
					meta = unitNames[compactBECUnitCode(unitCode)]
				}
				if !matchesFilter(baseLeaf, meta.longName) {
					continue
				}
				bucket := bucketMap[unitCode]
				if bucket == nil {
					bucket = &SUUnitBucket{
						SiteUnit:  unitCode,
						LongName:  meta.longName,
						Origin:    meta.origin,
						MaskValid: BECUnitMaskValid(unitCode),
						Plots:     []SUPlotLeaf{},
					}
					bucketMap[unitCode] = bucket
				}
				bucket.Plots = append(bucket.Plots, baseLeaf)
				bucket.PlotCount = len(bucket.Plots)
			}
			if err := errors.Join(suRows.Err(), suRows.Close()); err != nil {
				return nil, err
			}

			// Any project plot absent from <SU>_SU belongs in UnassignedPlots!
			for _, plotNum := range envOrder {
				if !seenSUPlot[plotNum] {
					leaf := envMap[plotNum]
					leaf.PresentInSU = false
					tree.TotalUnassigned++
					if matchesFilter(leaf, "") {
						tree.UnassignedPlots = append(tree.UnassignedPlots, leaf)
					}
				}
			}

			unitKeys := make([]string, 0, len(bucketMap))
			for k := range bucketMap {
				unitKeys = append(unitKeys, k)
			}
			slices.SortFunc(unitKeys, func(a, b string) int {
				if cmp := strings.Compare(strings.ToLower(a), strings.ToLower(b)); cmp != 0 {
					return cmp
				}
				return strings.Compare(a, b)
			})
			for _, k := range unitKeys {
				b := bucketMap[k]
				slices.SortFunc(b.Plots, func(x, y SUPlotLeaf) int {
					return strings.Compare(x.PlotNumber, y.PlotNumber)
				})
				tree.Units = append(tree.Units, *b)
			}
		}

		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return tree, nil
	})
}

func GetPlotInspectorSummary(ctx context.Context, contexts *vprocore.ContextService, contextID, plotNumber string) (*PlotInspectorSummary, error) {
	if ctx == nil {
		return nil, errors.New("plot inspector requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	if plotNumber == "" || !utf8.ValidString(plotNumber) || strings.ContainsRune(plotNumber, 0) {
		return nil, errors.New("plot inspector requires a valid literal plot number")
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (_ *PlotInspectorSummary, resultErr error) {
		owner := plots.Projects.Sqlite
		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return nil, err
		}
		defer unlock()
		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		tx, err := owner.BeginReadSnapshot(ctx)
		if err != nil {
			return nil, err
		}
		defer func() {
			if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
				resultErr = errors.Join(resultErr, rb)
			}
		}()

		project := owner.Selection.Project
		summary := &PlotInspectorSummary{
			ContextID:  contextID,
			PlotNumber: plotNumber,
			TopSpecies: []PlotInspectorSpecies{},
		}

		var elev, aspect sql.NullInt64
		var slope, lat, lon sql.NullFloat64
		err = tx.QueryRowContext(ctx,
			`SELECT CAST(env."PlotNumber" AS TEXT),
			        COALESCE(CAST(env."FieldNumber" AS TEXT), ''),
			        COALESCE(CAST(env."ProjectID" AS TEXT), ''),
			        COALESCE(CAST(env."Zone" AS TEXT), ''),
			        COALESCE(CAST(env."SubZone" AS TEXT), ''),
			        COALESCE(CAST(env."SiteSeries" AS TEXT), ''),
			        COALESCE(CAST(admin."UserSiteUnit" AS TEXT), ''),
			        COALESCE(CAST(admin."BECSiteUnit" AS TEXT), ''),
			        COALESCE(CAST(env."MoistureRegime" AS TEXT), ''),
			        COALESCE(CAST(env."NutrientRegime" AS TEXT), ''),
			        env."Elevation",
			        env."SlopeGradient",
			        env."Aspect",
			        env."Latitude",
			        env."Longitude"
			 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Env")+` AS env
			 LEFT JOIN "project".`+vprocore.QuoteHeaderIdentifier(project+"_Admin")+` AS admin
			   ON admin."Plot" = env."PlotNumber" AND typeof(admin."Plot")='text' AND CAST(admin."Plot" AS BLOB)=CAST(env."PlotNumber" AS BLOB)
			 WHERE env."PlotNumber" = ? AND typeof(env."PlotNumber")='text' AND CAST(env."PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
			plotNumber, plotNumber,
		).Scan(
			&summary.PlotNumber, &summary.FieldNumber, &summary.ProjectID,
			&summary.Zone, &summary.SubZone, &summary.SiteSeries,
			&summary.UserSiteUnit, &summary.BECSiteUnit,
			&summary.MoistureRegime, &summary.NutrientRegime,
			&elev, &slope, &aspect, &lat, &lon,
		)
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("plot %q not found in project %s", plotNumber, project)
		}
		if err != nil {
			return nil, err
		}
		if elev.Valid {
			v := elev.Int64
			summary.Elevation = &v
		}
		if slope.Valid {
			summary.Slope = reportcore.SiteUnitFixedNumber(slope.Float64, 1, 1)
		}
		if aspect.Valid {
			v := aspect.Int64
			summary.Aspect = &v
		}
		if lat.Valid {
			v := lat.Float64
			summary.Latitude = &v
		}
		if lon.Valid {
			v := lon.Float64
			summary.Longitude = &v
		}

		if owner.Selection.SU != "None" && owner.Selection.SU != "" {
			var suUnit sql.NullString
			suErr := tx.QueryRowContext(ctx,
				`SELECT CAST("SiteUnit" AS TEXT) FROM "su".`+vprocore.QuoteHeaderIdentifier(owner.Selection.SU+"_SU")+
					` WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
				plotNumber, plotNumber,
			).Scan(&suUnit)
			if suErr == nil && suUnit.Valid {
				summary.CurrentSUUnit = suUnit.String
			}
		}

		// Aggregate top species covers across A/B/C/D strata with IEEE-754 float32 narrowing + 99% fallback cap
		vegRows, err := tx.QueryContext(ctx,
			`SELECT COALESCE(CAST(v."Species" AS TEXT), ''),
			        v."TotalA", v."Cover1", v."Cover2", v."Cover3",
			        v."TotalB", v."Cover4", v."Cover5", v."Cover5a", v."Cover5b", v."Cover5c",
			        v."Cover6", v."Cover7", v."Cover8", v."Cover9", v."Cover10"
			 FROM "project".`+vprocore.QuoteHeaderIdentifier(project+"_Veg")+` AS v
			 WHERE v."PlotNumber" = ? AND typeof(v."PlotNumber")='text' AND CAST(v."PlotNumber" AS BLOB)=CAST(? AS BLOB)`,
			plotNumber, plotNumber,
		)
		if err != nil {
			return nil, err
		}
		type aggSp struct {
			code       string
			a, b, c, d float64
		}
		aggMap := map[string]*aggSp{}
		stratumWithFallback := func(explicit sql.NullFloat64, sublayers ...sql.NullFloat64) float64 {
			if explicit.Valid {
				return float64(float32(explicit.Float64))
			}
			var sum float32
			for _, sub := range sublayers {
				if sub.Valid {
					sum += float32(sub.Float64)
				}
			}
			if sum > 99 {
				sum = 99
			}
			return float64(sum)
		}
		for vegRows.Next() {
			var sp string
			var totalA, c1, c2, c3 sql.NullFloat64
			var totalB, c4, c5, c5a, c5b, c5c sql.NullFloat64
			var c6, c7, c8, c9, c10 sql.NullFloat64
			if err := vegRows.Scan(&sp, &totalA, &c1, &c2, &c3, &totalB, &c4, &c5, &c5a, &c5b, &c5c, &c6, &c7, &c8, &c9, &c10); err != nil {
				vegRows.Close()
				return nil, err
			}
			ca := stratumWithFallback(totalA, c1, c2, c3)
			cb := stratumWithFallback(totalB, c4, c5, c5a, c5b, c5c)
			cc := float64(float32(c6.Float64))
			cd := float64(float32(c7.Float64) + float32(c8.Float64) + float32(c9.Float64) + float32(c10.Float64))
			upper := strings.ToUpper(strings.TrimSpace(sp))
			if upper == "" {
				continue
			}
			item := aggMap[upper]
			if item == nil {
				item = &aggSp{code: strings.TrimSpace(sp)}
				aggMap[upper] = item
			}
			item.a += ca
			item.b += cb
			item.c += cc
			item.d += cd
		}
		if err := errors.Join(vegRows.Err(), vegRows.Close()); err != nil {
			return nil, err
		}

		aggList := make([]*aggSp, 0, len(aggMap))
		for _, item := range aggMap {
			aggList = append(aggList, item)
		}
		slices.SortFunc(aggList, func(x, y *aggSp) int {
			txTotal := x.a + x.b + x.c + x.d
			tyTotal := y.a + y.b + y.c + y.d
			if txTotal > tyTotal {
				return -1
			}
			if txTotal < tyTotal {
				return 1
			}
			return strings.Compare(x.code, y.code)
		})
		if len(aggList) > 15 {
			aggList = aggList[:15]
		}

		for _, item := range aggList {
			var sci, eng sql.NullString
			_ = tx.QueryRowContext(ctx,
				`SELECT CAST("ScientificName" AS TEXT), CAST("EnglishName" AS TEXT)
				 FROM "VLists"."USysAllSpecs" WHERE UPPER("Code") = UPPER(?) AND COALESCE("Codetype",'u') <> 's' LIMIT 1`,
				item.code,
			).Scan(&sci, &eng)
			if !sci.Valid {
				_ = tx.QueryRowContext(ctx,
					`SELECT CAST("ScientificName" AS TEXT), CAST("EnglishName" AS TEXT)
					 FROM "VUser"."USysUserSpp" WHERE UPPER("Code") = UPPER(?) LIMIT 1`,
					item.code,
				).Scan(&sci, &eng)
			}
			tot := item.a + item.b + item.c + item.d
			fmtStratum := func(v float64) string {
				if v == 0 {
					return ""
				}
				return reportcore.SiteUnitFixedNumber(v, 1, 1)
			}
			summary.TopSpecies = append(summary.TopSpecies, PlotInspectorSpecies{
				Species:        item.code,
				ScientificName: sci.String,
				EnglishName:    eng.String,
				CoverA:         fmtStratum(item.a),
				CoverB:         fmtStratum(item.b),
				CoverC:         fmtStratum(item.c),
				CoverD:         fmtStratum(item.d),
				TotalCover:     tot,
				TotalFormatted: reportcore.SiteUnitFixedNumber(tot, 1, 1),
			})
		}

		if err := vprocore.ProfileOwnedFiles(owner); err != nil {
			return nil, err
		}
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return summary, nil
	})
}
