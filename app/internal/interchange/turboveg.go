package interchange

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"strings"
	"sync/atomic"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

var tvFallbackUUIDSeq uint64

func newTurboVegUUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		seq := atomic.AddUint64(&tvFallbackUUIDSeq, 1)
		now := uint64(time.Now().UnixNano())
		for i := 0; i < 8; i++ {
			b[i] = byte(now >> (8 * i))
			b[8+i] = byte(seq >> (8 * i))
		}
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var out [36]byte
	hex.Encode(out[0:8], b[0:4])
	out[8] = '-'
	hex.Encode(out[9:13], b[4:6])
	out[13] = '-'
	hex.Encode(out[14:18], b[6:8])
	out[18] = '-'
	hex.Encode(out[19:23], b[8:10])
	out[23] = '-'
	hex.Encode(out[24:36], b[10:16])
	return string(out[:])
}

func nullTruncatedUTF16(s string, maxUnits int) any {
	trimmed := strings.TrimSpace(s)
	if maxUnits > 0 {
		trimmed = sqlutil.TruncateUTF16(trimmed, maxUnits)
	}
	if trimmed == "" {
		return nil
	}
	return trimmed
}

func validateFiniteSingleFloat(v float64, label string, nonNegative bool) (float64, error) {
	if math.IsNaN(v) || math.IsInf(v, 0) || math.Abs(v) > math.MaxFloat32 || (nonNegative && v < 0) {
		return 0, fmt.Errorf("%s %v is out of numeric range", label, v)
	}
	return float64(float32(v)), nil
}

func validateUTF8Text(s, label string) error {
	if !utf8.ValidString(s) || strings.ContainsRune(s, 0) {
		return fmt.Errorf("%s contains malformed UTF-8 or NUL byte", label)
	}
	return nil
}
func nullEmpty(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}

func accumulateImportedSingleCover(covers map[string]float64, col string, obsCov float64, plotNum, species string) error {
	if math.IsNaN(obsCov) || math.IsInf(obsCov, 0) || obsCov < 0 || math.Abs(obsCov) > math.MaxFloat32 || float32(obsCov) >= 100 {
		return fmt.Errorf("plot %s species %s cover %v must be from 0 to under 100%% (e.g. 99.9%%)", plotNum, species, obsCov)
	}
	obsSingle := float64(float32(obsCov))
	prev, hasPrev := covers[col]
	if !hasPrev {
		covers[col] = obsSingle
		return nil
	}
	sumSingle := float32(prev + obsSingle)
	if sumSingle > 99 { // AGENTS.md §3.3: summed (lumped) covers are capped at 99%
		covers[col] = 99.0
	} else {
		covers[col] = float64(sumSingle)
	}
	return nil
}

const (
	TurboVegFormatXML    = "xml"
	TurboVegFormatSQLite = "sqlite"
)

// Official Alterra Turboveg 3 fixed vegetationlayers (0..10, non-extensible per Alterra specification).
type tvVegetationLayerDef struct {
	ID           int
	Name         string
	Abbreviation string
	Description  string
}

var canonicalTV3VegetationLayers = []tvVegetationLayerDef{
	{0, "-", "-", "no layer defined"},
	{1, "Tree layer 1", "t1", "Tree layer 1"},
	{2, "Tree layer 2", "t2", "Tree layer 2"},
	{3, "Tree layer 3", "t3", "Tree layer 3"},
	{4, "Shrub layer 1", "s1", "Shrub layer 1"},
	{5, "Shrub layer 2", "s2", "Shrub layer 2"},
	{6, "Herb layer", "hl", "Herb layer"},
	{7, "Juvenile layer", "jl", "Juvenile layer"},
	{8, "Seedling layer", "sl", "Seedling layer"},
	{9, "Cryptogam layer", "ml", "Cryptogam layer"},
	{10, "Epiphytes", "ep", "Epiphytes"},
}

type turboVegLayerCrosswalk struct {
	VProLayer string
	TVLayerID int
	IsPrimary bool
}

var turboVegCrosswalk = []turboVegLayerCrosswalk{
	{"A1", 1, true},
	{"A2", 2, true},
	{"A3", 3, true},
	{"A", 1, false},
	{"B1", 4, true},
	{"B2", 5, true},
	{"B2a", 5, false},
	{"B2b", 5, false},
	{"B2c", 5, false},
	{"B", 4, false},
	{"C", 6, true},
	{"D", 9, true},
	{"Dw", 9, false},
	{"Dr", 9, false},
	{"Ep", 10, true},
}

var vproSublayerCodeToTV = func() map[string]turboVegLayerCrosswalk {
	m := make(map[string]turboVegLayerCrosswalk, len(turboVegCrosswalk))
	for _, cw := range turboVegCrosswalk {
		m[cw.VProLayer] = cw
	}
	return m
}()

func isWoodyVProLifeform(lf *int) bool {
	if lf == nil {
		return false
	}
	switch *lf {
	case 1, 2, 3, 4, 12:
		return true
	default:
		return false
	}
}

func taxonGroupForLifeform(lf *int) int {
	if lf == nil {
		return 1
	}
	switch *lf {
	case 9, 10:
		return 3 // Mosses & liverworts
	case 11:
		return 4 // Lichens
	case 13:
		return 6 // Algae
	default:
		return 1 // Vascular plants
	}
}

func taxonRankForSciName(sci string) int {
	lower := strings.ToLower(sci)
	if strings.Contains(lower, " var. ") {
		return 4 // Variety
	}
	if strings.Contains(lower, " ssp. ") || strings.Contains(lower, " subsp. ") {
		return 3 // Subspecies
	}
	if strings.HasSuffix(lower, " spp.") || strings.HasSuffix(lower, " sp.") || !strings.Contains(strings.TrimSpace(sci), " ") {
		return 1 // Genus
	}
	return 2 // Species
}

func resolveIncomingTurboVegLayer(tvLayer, vproLayer string, isWoody bool) (coverCol, heightCol string) {
	switch strings.ToUpper(strings.TrimSpace(vproLayer)) {
	case "A1":
		return "Cover1", "Height1"
	case "A2":
		return "Cover2", "Height2"
	case "A3":
		return "Cover3", "Height3"
	case "A", "TOTALA":
		return "TotalA", "HeightA"
	case "B1":
		return "Cover4", "Height4"
	case "B2":
		return "Cover5", "Height5"
	case "B2A", "5A":
		return "Cover5a", "Height5a"
	case "B2B", "5B":
		return "Cover5b", "Height5b"
	case "B2C", "5C":
		return "Cover5c", "Height5c"
	case "B", "TOTALB":
		return "TotalB", "HeightB"
	case "C":
		return "Cover6", "Height6"
	case "D", "DH":
		return "Cover7", ""
	case "DW":
		return "Cover8", ""
	case "DR":
		return "Cover9", ""
	case "EP":
		return "Cover10", ""
	}

	switch strings.ToLower(strings.TrimSpace(tvLayer)) {
	case "1", "t1":
		return "Cover1", "Height1"
	case "2", "t2":
		return "Cover2", "Height2"
	case "3", "t3":
		return "Cover3", "Height3"
	case "4", "s1":
		return "Cover4", "Height4"
	case "5", "s2":
		return "Cover5", "Height5"
	case "6", "hl":
		return "Cover6", "Height6"
	case "7", "jl":
		if isWoody {
			return "Cover5", "Height5"
		}
		return "Cover6", "Height6"
	case "8", "sl":
		return "Cover6", "Height6"
	case "9", "ml":
		return "Cover7", ""
	case "10", "ep":
		return "Cover10", ""
	default:
		return "Cover6", "Height6"
	}
}

type TurboVegExportRequest struct {
	Format          string `json:"format"` // "xml" | "sqlite"
	DestinationPath string `json:"destinationPath"`
	LumpTable       string `json:"lumpTable,omitempty"`
	LumpDBPath      string `json:"lumpDbPath,omitempty"`
}

func (r *TurboVegExportRequest) UnmarshalJSON(data []byte) error {
	type plain TurboVegExportRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type TurboVegExportOutcome struct {
	Format           string `json:"format"`
	Path             string `json:"path"`
	SHA256           string `json:"sha256"`
	PlotCount        int    `json:"plotCount"`
	SpeciesCount     int    `json:"speciesCount"`
	ObservationCount int    `json:"observationCount"`
}

type TurboVegImportRequest struct {
	SourcePath        string `json:"sourcePath"`
	Format            string `json:"format,omitempty"` // "xml" | "sqlite" (inferred from extension if omitted)
	TargetProject     string `json:"targetProject"`
	DestinationPath   string `json:"destinationPath,omitempty"`
	ActivateOnSuccess bool   `json:"activateOnSuccess"`
	// ResolveVProCodeSynonyms maps explicit incoming vpro_code UDF/JSON entries that match
	// a USysAllSpecs Codetype='S' synonym (OldCode) onto their canonical USysAllSpecs.Code.
	// When false (default), explicit vpro_code values are preserved verbatim while adopting
	// matched synonym Lifeform metadata.
	ResolveVProCodeSynonyms bool `json:"resolveVProCodeSynonyms,omitempty"`
}

func (r *TurboVegImportRequest) UnmarshalJSON(data []byte) error {
	type plain TurboVegImportRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type TurboVegImportOutcome struct {
	SourcePath       string                 `json:"sourcePath"`
	Format           string                 `json:"format"`
	TargetProject    string                 `json:"targetProject"`
	DestinationPath  string                 `json:"destinationPath"`
	DestinationSHA   string                 `json:"destinationSha256"`
	PlotCount        int                    `json:"plotCount"`
	SpeciesCount     int                    `json:"speciesCount"`
	ObservationCount int                    `json:"observationCount"`
	Activated        bool                   `json:"activated"`
	State            *vprocore.ProjectState `json:"state,omitempty"`
}

type tvPlotHeader struct {
	PlotID            int
	GUID              string
	PlotNumber        string
	FieldNumber       string
	ProjectID         string
	Date              string
	Latitude          *float64
	Longitude         *float64
	Elevation         *int
	Slope             *float64
	Aspect            *int
	PlotSize          *float64
	Zone              string
	SubZone           string
	SiteSeries        string
	SiteUnit          string
	MoistureRegime    string
	NutrientRegime    string
	MesoSlopePosition string
	SurfaceShape      string
	SoilDrainage      string
	HumusForm         string
	Surveyor          string
	Location          string
	SiteNotes         string
	VegNotes          string
	SoilNotes         string
}

type tvExportObs struct {
	SpeciesNR   int
	SpeciesCode string
	SciName     string
	TVLayerID   int
	VProLayer   string
	Cover       float64
	Height      *float64
	Collected   string
}

type tvImportObs struct {
	SpeciesCode string
	TVLayerRaw  string
	VProLayer   string
	IsWoody     bool
	Cover       float64
	Height      *float64
	Collected   string
}

type tvDataset struct {
	ProjectName string
	Species     []tvSpeciesItem
	Plots       []tvExportPlot
}

type tvSpeciesItem struct {
	SpeciesNR      int
	SpeciesCode    string
	LetterCode     string
	ScientificName string
	EnglishName    string
	Lifeform       *int
	Authority      string
}

type tvExportPlot struct {
	Header       tvPlotHeader
	Observations []tvExportObs
}

type tvImportPlot struct {
	Header       tvPlotHeader
	Observations []tvImportObs
}

type speciesResolvedInfo struct {
	Code     string
	Lifeform *int
}

type speciesImportResolver struct {
	byActiveCode            map[string]speciesResolvedInfo
	bySynonymCode           map[string]speciesResolvedInfo
	byUserCode              map[string]speciesResolvedInfo
	bySciFull               map[string]speciesResolvedInfo
	bySciCanon              map[string]speciesResolvedInfo
	resolveVProCodeSynonyms bool
}

func normalizeScientificFull(raw string) string {
	s := strings.ToLower(strings.TrimSpace(raw))
	if s == "" {
		return ""
	}
	s = strings.ReplaceAll(s, "×", "x")
	s = strings.ReplaceAll(s, "subsp.", "ssp.")
	fields := strings.Fields(s)
	return strings.Join(fields, " ")
}

// canonicalScientificTaxon extracts normalized "genus species [ssp.|var.|f. epithet]"
// stripping trailing botanical authorities or "agg." / "s.l." qualifiers when present.
func canonicalScientificTaxon(raw string) string {
	norm := normalizeScientificFull(raw)
	if norm == "" {
		return ""
	}
	tokens := strings.Fields(norm)
	if len(tokens) == 1 {
		return tokens[0]
	}
	if tokens[1] == "x" && len(tokens) >= 3 {
		base := tokens[0] + " x " + tokens[2]
		if len(tokens) >= 5 && (tokens[3] == "ssp." || tokens[3] == "var." || tokens[3] == "f.") {
			return base + " " + tokens[3] + " " + tokens[4]
		}
		return base
	}
	if tokens[1] == "spp." || tokens[1] == "sp." {
		return tokens[0] + " spp."
	}
	base := tokens[0] + " " + tokens[1]
	for i := 2; i+1 < len(tokens); i++ {
		if tokens[i] == "ssp." || tokens[i] == "var." || tokens[i] == "f." {
			return base + " " + tokens[i] + " " + tokens[i+1]
		}
	}
	return base
}

func loadSpeciesImportResolver(ctx context.Context, tx *sql.Tx) (*speciesImportResolver, error) {
	r := &speciesImportResolver{
		byActiveCode:  make(map[string]speciesResolvedInfo, 12000),
		bySynonymCode: make(map[string]speciesResolvedInfo, 6000),
		byUserCode:    make(map[string]speciesResolvedInfo, 256),
		bySciFull:     make(map[string]speciesResolvedInfo, 16000),
		bySciCanon:    make(map[string]speciesResolvedInfo, 16000),
	}

	rows, err := tx.QueryContext(ctx, `
		SELECT COALESCE(Code,''), COALESCE(OldCode,''), COALESCE(ScientificName,''), Lifeform, COALESCE(Codetype,'')
		FROM VLists.USysAllSpecs
		WHERE Code IS NOT NULL AND TRIM(Code) <> ''
		ORDER BY CASE
			WHEN UPPER(COALESCE(Codetype,''))='U' THEN 0
			WHEN UPPER(COALESCE(Codetype,''))<>'S' THEN 1
			ELSE 2
		END, rowid`)
	if err != nil {
		return nil, err
	}
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, rows.Close()) }()
		for rows.Next() {
			var code, oldCode, sci, ctype string
			var lf sql.NullInt64
			if err := rows.Scan(&code, &oldCode, &sci, &lf, &ctype); err != nil {
				return err
			}
			uCode := strings.ToUpper(strings.TrimSpace(code))
			if uCode == "" {
				continue
			}
			var lfPtr *int
			if lf.Valid {
				v := int(lf.Int64)
				lfPtr = &v
			}
			info := speciesResolvedInfo{Code: uCode, Lifeform: lfPtr}
			isSyn := strings.EqualFold(strings.TrimSpace(ctype), "S")
			if !isSyn {
				if _, exists := r.byActiveCode[uCode]; !exists {
					r.byActiveCode[uCode] = info
				}
			} else {
				uOld := strings.ToUpper(strings.TrimSpace(oldCode))
				if uOld != "" {
					if _, exists := r.bySynonymCode[uOld]; !exists {
						r.bySynonymCode[uOld] = info
					}
				}
			}
			if full := normalizeScientificFull(sci); full != "" {
				if _, exists := r.bySciFull[full]; !exists {
					r.bySciFull[full] = info
				}
			}
			if canon := canonicalScientificTaxon(sci); canon != "" {
				if _, exists := r.bySciCanon[canon]; !exists {
					r.bySciCanon[canon] = info
				}
			}
		}
		return rows.Err()
	}(); err != nil {
		return nil, err
	}

	uRows, err := tx.QueryContext(ctx, `
		SELECT COALESCE(Code,''), COALESCE(ScientificName,''), LifeForm, COALESCE(Codetype,'')
		FROM VUser.USysUserSpp
		WHERE Code IS NOT NULL AND TRIM(Code) <> ''`)
	if err != nil {
		return nil, err
	}
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, uRows.Close()) }()
		for uRows.Next() {
			var code, sci, ctype string
			var lf sql.NullInt64
			if err := uRows.Scan(&code, &sci, &lf, &ctype); err != nil {
				return err
			}
			if strings.EqualFold(strings.TrimSpace(ctype), "S") {
				continue
			}
			uCode := strings.ToUpper(strings.TrimSpace(code))
			if uCode == "" {
				continue
			}
			var lfPtr *int
			if lf.Valid {
				v := int(lf.Int64)
				lfPtr = &v
			}
			info := speciesResolvedInfo{Code: uCode, Lifeform: lfPtr}
			if _, exists := r.byUserCode[uCode]; !exists {
				r.byUserCode[uCode] = info
			}
			if full := normalizeScientificFull(sci); full != "" {
				if _, exists := r.bySciFull[full]; !exists {
					r.bySciFull[full] = info
				}
			}
			if canon := canonicalScientificTaxon(sci); canon != "" {
				if _, exists := r.bySciCanon[canon]; !exists {
					r.bySciCanon[canon] = info
				}
			}
		}
		return uRows.Err()
	}(); err != nil {
		return nil, err
	}
	return r, nil
}

func (r *speciesImportResolver) resolveTaxon(explicitVProCode, sciName, validSciName, letterCode string) (code string, lifeform *int) {
	if v := strings.ToUpper(strings.TrimSpace(explicitVProCode)); v != "" {
		if r != nil {
			if info, ok := r.byActiveCode[v]; ok {
				return v, info.Lifeform
			}
			if info, ok := r.byUserCode[v]; ok {
				return v, info.Lifeform
			}
			if info, ok := r.bySynonymCode[v]; ok {
				if r.resolveVProCodeSynonyms && info.Code != "" {
					return info.Code, info.Lifeform
				}
				return v, info.Lifeform
			}
		}
		return v, nil
	}

	if r != nil {
		for _, candidateSci := range []string{validSciName, sciName} {
			if full := normalizeScientificFull(candidateSci); full != "" {
				if info, ok := r.bySciFull[full]; ok {
					return info.Code, info.Lifeform
				}
			}
			if canon := canonicalScientificTaxon(candidateSci); canon != "" {
				if info, ok := r.bySciCanon[canon]; ok {
					return info.Code, info.Lifeform
				}
			}
		}
		if lc := strings.ToUpper(strings.TrimSpace(letterCode)); lc != "" {
			if info, ok := r.byActiveCode[lc]; ok {
				return info.Code, info.Lifeform
			}
			if info, ok := r.bySynonymCode[lc]; ok {
				return info.Code, info.Lifeform
			}
			if info, ok := r.byUserCode[lc]; ok {
				return info.Code, info.Lifeform
			}
		}
	}

	if lc := strings.ToUpper(strings.TrimSpace(letterCode)); lc != "" {
		return lc, nil
	}
	for _, candidateSci := range []string{validSciName, sciName} {
		if abbr := abbreviateSpeciesName(candidateSci); abbr != "" {
			return abbr, nil
		}
	}
	return "", nil
}

func enrichExportSpeciesMetaWithOldCodes(ctx context.Context, tx *sql.Tx, sppMeta map[string]speciesLookupMeta) error {
	rows, err := tx.QueryContext(ctx, `
		SELECT COALESCE(OldCode,''), COALESCE(ScientificName,''), COALESCE(EnglishName,''), COALESCE(Authority,''), Lifeform
		FROM VLists.USysAllSpecs
		WHERE OldCode IS NOT NULL AND TRIM(OldCode) <> ''`)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var oldCode, sci, eng, auth string
		var lf sql.NullInt64
		if err := rows.Scan(&oldCode, &sci, &eng, &auth, &lf); err != nil {
			return err
		}
		uOld := strings.ToUpper(strings.TrimSpace(oldCode))
		if uOld == "" {
			continue
		}
		if _, exists := sppMeta[uOld]; exists {
			continue
		}
		var lfPtr *int
		if lf.Valid {
			v := int(lf.Int64)
			lfPtr = &v
		}
		sppMeta[uOld] = speciesLookupMeta{
			ScientificName: strings.TrimSpace(sci),
			EnglishName:    strings.TrimSpace(eng),
			Authority:      strings.TrimSpace(auth),
			Lifeform:       lfPtr,
		}
	}
	return rows.Err()
}
