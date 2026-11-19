package main

import (
	"database/sql"
	"sort"
	"strconv"
	"strings"
	"unicode"

	"github.com/boostao/vpro/app/internal/accessreader"
)

type specsRow struct {
	YearOfChange        *string
	ChangeDescription   *string
	APCFamily           *string
	FamilyCode          *string
	OldCode             *string
	Code                *string
	SplCode             *string
	TreeCode            *string
	ScientificName      *string
	Lifeform            *int64
	Authority           *string
	EnglishNameOld      *string
	EnglishName         *string
	CommonNamePB        *string
	NotesOnNames        *string
	ShortenedGuideName  *string
	Native              *string
	Codetype            *string
	Province            *string
	ID                  *int64
	TaxonLevel          *string
	IsAttribute         int64
	Report              *int64
	SplCodeCalc         *string
	Codelength          *int64
	CombinedEnglishName *string
}

type historicalSpecsIndex struct {
	rows         []specsRow
	byCodeNonSyn map[string]int
	bySci        map[string][]int
	genusFamily  map[string][2]*string
	usedOldCodes map[string]bool
	consumed     []bool
	nextID       int64
}

type parsed2025TaxaRow struct {
	yoc    *string
	chg    *string
	sci    *string
	eng    *string
	short  *string
	code   *string
	spl    *string
	nat    *string
	ct     *string
	taxLvl *string
	lf     *int64
	tree   *string
	isAttr int64
}

func deriveBECSynonymOldCode(sci string, targetCode string, usedOldCodes map[string]bool) string {
	fields := strings.Fields(sci)
	if len(fields) == 0 {
		return strings.ToUpper(targetCode)
	}
	genus := asciiUpperLetters(fields[0])
	if len(genus) > 4 {
		genus = genus[:4]
	}
	species := extractSpeciesEpithetPrefix(fields)
	base := genus + species
	if base == "" {
		base = strings.ToUpper(targetCode)
	}
	isInfra := hasInfraspecificMarker(fields)
	if !isInfra && !strings.EqualFold(base, targetCode) {
		return base
	}
	for n := 1; n <= 9; n++ {
		cand := base + strconv.Itoa(n)
		if len(cand) <= 8 && !strings.EqualFold(cand, targetCode) && !usedOldCodes[cand] {
			return cand
		}
	}
	return base
}

func asciiUpperLetters(s string) string {
	var b strings.Builder
	for _, r := range s {
		if unicode.IsLetter(r) {
			b.WriteRune(unicode.ToUpper(r))
		}
	}
	return b.String()
}

func extractSpeciesEpithetPrefix(fields []string) string {
	species := ""
	if len(fields) >= 2 {
		ep := fields[1]
		if strings.EqualFold(ep, "x") && len(fields) >= 3 {
			species = "X" + asciiUpperLetters(fields[2])
		} else {
			species = asciiUpperLetters(ep)
		}
	}
	if len(species) > 3 {
		return species[:3]
	}
	return species
}

func hasInfraspecificMarker(fields []string) bool {
	for _, f := range fields {
		lf := strings.ToLower(strings.TrimSuffix(f, "."))
		if lf == "ssp" || lf == "subsp" || lf == "var" {
			return true
		}
	}
	return false
}

func genusKey(sci string) string {
	fields := strings.Fields(sci)
	if len(fields) == 0 {
		return ""
	}
	return strings.ToLower(fields[0])
}

func normSciKey(s string) string {
	return strings.ToLower(strings.Join(strings.Fields(s), " "))
}

func mergeTaxonomy2025(taxaAccdb *accessreader.DB, vlistsDB *sql.DB) ([]specsRow, error) {
	histIdx, err := loadHistoricalUSysAllSpecs(vlistsDB)
	if err != nil {
		return nil, err
	}
	_, taxa2025, err := taxaAccdb.ReadAll("USysAllSpecs")
	if err != nil {
		return nil, err
	}

	var out []specsRow
	// Pass 1: Process non-synonym 2025 rows first so they deterministically claim their Code rows.
	for _, tr := range taxa2025 {
		parsed := parse2025TaxaRecord(tr)
		if strings.EqualFold(strVal(parsed.ct), "S") {
			continue
		}
		out = append(out, histIdx.mergeNonSynonymRow(parsed))
	}

	// Pass 2: Process synonym (Codetype == 'S') 2025 rows against remaining unconsumed historical rows.
	for _, tr := range taxa2025 {
		parsed := parse2025TaxaRecord(tr)
		if !strings.EqualFold(strVal(parsed.ct), "S") {
			continue
		}
		out = append(out, histIdx.mergeSynonymRow(parsed))
	}

	// Retain all unconsumed historical rows so ZERO OldCode -> Code synonyms or historical codes are lost!
	for i, hr := range histIdx.rows {
		if !histIdx.consumed[i] {
			out = append(out, hr)
		}
	}

	resolveChainedSynonyms(out)
	propagateGenusAndCodeFamilies(out, histIdx.genusFamily)
	out = ensureLMH25TreeCodeAcx(out, &histIdx.nextID)
	sortMergedSpecsRows(out)
	return out, nil
}

func loadHistoricalUSysAllSpecs(vlistsDB *sql.DB) (*historicalSpecsIndex, error) {
	rows, err := vlistsDB.Query(`SELECT
		YearOfChange, ChangeDescription, APCFamily, FamilyCode, OldCode, Code, SplCode, TreeCode,
		ScientificName, Lifeform, Authority, EnglishName_Old, EnglishName, common_name_pb,
		Notes_on_names, ShortenedGuideName, Native, Codetype, Province, ID, TaxonLevel,
		COALESCE(IsAttribute, 0), Report, SplCode_calc, Codelength, CombinedEnglishName
		FROM USysAllSpecs
		ORDER BY COALESCE(ID, 0), COALESCE(OldCode, ''), COALESCE(Code, ''), COALESCE(ScientificName, '')`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	idx := &historicalSpecsIndex{
		byCodeNonSyn: map[string]int{},
		bySci:        map[string][]int{},
		genusFamily:  map[string][2]*string{},
		usedOldCodes: map[string]bool{},
		nextID:       19000001,
	}
	for rows.Next() {
		var r specsRow
		if err := rows.Scan(
			&r.YearOfChange, &r.ChangeDescription, &r.APCFamily, &r.FamilyCode, &r.OldCode, &r.Code, &r.SplCode, &r.TreeCode,
			&r.ScientificName, &r.Lifeform, &r.Authority, &r.EnglishNameOld, &r.EnglishName, &r.CommonNamePB,
			&r.NotesOnNames, &r.ShortenedGuideName, &r.Native, &r.Codetype, &r.Province, &r.ID, &r.TaxonLevel,
			&r.IsAttribute, &r.Report, &r.SplCodeCalc, &r.Codelength, &r.CombinedEnglishName,
		); err != nil {
			return nil, err
		}
		if r.ID != nil && *r.ID >= 19000001 {
			continue
		}
		idx.indexHistoricalRow(r)
	}
	idx.consumed = make([]bool, len(idx.rows))
	return idx, rows.Err()
}

func (h *historicalSpecsIndex) indexHistoricalRow(r specsRow) {
	pos := len(h.rows)
	h.rows = append(h.rows, r)
	if r.OldCode != nil && *r.OldCode != "" {
		h.usedOldCodes[strings.ToUpper(*r.OldCode)] = true
	}
	if r.Code != nil && *r.Code != "" && !strings.EqualFold(strVal(r.Codetype), "S") {
		cu := strings.ToUpper(*r.Code)
		if prevIdx, seen := h.byCodeNonSyn[cu]; !seen || (!strings.EqualFold(strVal(h.rows[prevIdx].Codetype), "U") && strings.EqualFold(strVal(r.Codetype), "U")) {
			h.byCodeNonSyn[cu] = pos
		}
	}
	if r.ScientificName != nil && *r.ScientificName != "" {
		sk := normSciKey(*r.ScientificName)
		h.bySci[sk] = append(h.bySci[sk], pos)
		if gk := genusKey(*r.ScientificName); gk != "" && r.APCFamily != nil && r.FamilyCode != nil {
			if _, ok := h.genusFamily[gk]; !ok {
				h.genusFamily[gk] = [2]*string{r.APCFamily, r.FamilyCode}
			}
		}
	}
}

func parse2025TaxaRecord(tr []any) parsed2025TaxaRow {
	var lf *int64
	if v, ok := tr[10].(int64); ok {
		vc := v
		lf = &vc
	}
	isAttr := int64(0)
	if b, ok := tr[12].(bool); ok && b {
		isAttr = -1
	}
	return parsed2025TaxaRow{
		yoc:    optStr(tr[0]),
		chg:    optStr(tr[1]),
		sci:    optStr(tr[2]),
		eng:    optStr(tr[3]),
		short:  optStr(tr[4]),
		code:   optStr(tr[5]),
		spl:    optStr(tr[6]),
		nat:    optStr(tr[7]),
		ct:     optStr(tr[8]),
		taxLvl: optStr(tr[9]),
		lf:     lf,
		tree:   optStr(tr[11]),
		isAttr: isAttr,
	}
}

func apply2025TaxaOverlay(base *specsRow, p parsed2025TaxaRow) {
	if p.yoc != nil {
		base.YearOfChange = p.yoc
	}
	if p.chg != nil {
		base.ChangeDescription = p.chg
	}
	base.ScientificName = p.sci
	if p.eng != nil {
		base.EnglishName = p.eng
	}
	if p.short != nil {
		base.ShortenedGuideName = p.short
	}
	base.Code = p.code
	base.SplCode = p.spl
	if p.nat != nil {
		base.Native = p.nat
	}
	base.Codetype = p.ct
	if p.taxLvl != nil {
		base.TaxonLevel = p.taxLvl
	}
	if p.lf != nil {
		base.Lifeform = p.lf
	}
	if p.tree != nil {
		base.TreeCode = p.tree
	}
	base.IsAttribute = p.isAttr
}

func (h *historicalSpecsIndex) lookupGenusFamily(sci *string) (*string, *string) {
	if gk := genusKey(strVal(sci)); gk != "" {
		if fam, ok := h.genusFamily[gk]; ok {
			return fam[0], fam[1]
		}
	}
	return nil, nil
}

func (h *historicalSpecsIndex) mergeNonSynonymRow(p parsed2025TaxaRow) specsRow {
	cu := strings.ToUpper(strVal(p.code))
	matchedIdx := h.findNonSynonymMatch(p.sci, cu)
	if matchedIdx >= 0 {
		h.consumed[matchedIdx] = true
		base := h.rows[matchedIdx]
		apply2025TaxaOverlay(&base, p)
		if base.OldCode == nil || strings.EqualFold(*base.OldCode, cu) {
			base.OldCode = p.code
		}
		return base
	}
	idVal := h.nextID
	h.nextID++
	apcFam, famCode := h.lookupGenusFamily(p.sci)
	provBC, repOne := "BC", int64(1)
	cl := int64(len(strVal(p.code)))
	return specsRow{
		YearOfChange: p.yoc, ChangeDescription: p.chg, APCFamily: apcFam, FamilyCode: famCode,
		OldCode: p.code, Code: p.code, SplCode: p.spl, TreeCode: p.tree, ScientificName: p.sci,
		Lifeform: p.lf, EnglishName: p.eng, ShortenedGuideName: p.short, Native: p.nat,
		Codetype: p.ct, Province: &provBC, ID: &idVal, TaxonLevel: p.taxLvl,
		IsAttribute: p.isAttr, Report: &repOne, SplCodeCalc: p.spl, Codelength: &cl,
	}
}

func (h *historicalSpecsIndex) findNonSynonymMatch(sci *string, codeUpper string) int {
	if sci != nil {
		for _, candIdx := range h.bySci[normSciKey(*sci)] {
			if !h.consumed[candIdx] && !strings.EqualFold(strVal(h.rows[candIdx].Codetype), "S") && strings.EqualFold(strVal(h.rows[candIdx].Code), codeUpper) {
				return candIdx
			}
		}
	}
	if idx, ok := h.byCodeNonSyn[codeUpper]; ok && !h.consumed[idx] {
		return idx
	}
	return -1
}

func (h *historicalSpecsIndex) mergeSynonymRow(p parsed2025TaxaRow) specsRow {
	matchedIdx := -1
	for _, candIdx := range h.bySci[normSciKey(strVal(p.sci))] {
		if !h.consumed[candIdx] {
			matchedIdx = candIdx
			break
		}
	}
	if matchedIdx >= 0 {
		h.consumed[matchedIdx] = true
		base := h.rows[matchedIdx]
		apply2025TaxaOverlay(&base, p)
		if base.OldCode == nil || *base.OldCode == "" {
			oc := deriveBECSynonymOldCode(strVal(p.sci), strVal(p.code), h.usedOldCodes)
			h.usedOldCodes[oc] = true
			base.OldCode = &oc
		}
		return base
	}
	idVal := h.nextID
	h.nextID++
	oc := deriveBECSynonymOldCode(strVal(p.sci), strVal(p.code), h.usedOldCodes)
	h.usedOldCodes[oc] = true
	apcFam, famCode := h.lookupGenusFamily(p.sci)
	provBC, repZero := "BC", int64(0)
	cl := int64(len(oc))
	return specsRow{
		YearOfChange: p.yoc, ChangeDescription: p.chg, APCFamily: apcFam, FamilyCode: famCode,
		OldCode: &oc, Code: p.code, SplCode: p.spl, TreeCode: p.tree, ScientificName: p.sci,
		Lifeform: p.lf, EnglishName: p.eng, ShortenedGuideName: p.short, Native: p.nat,
		Codetype: p.ct, Province: &provBC, ID: &idVal, TaxonLevel: p.taxLvl,
		IsAttribute: p.isAttr, Report: &repZero, SplCodeCalc: p.spl, Codelength: &cl,
	}
}

func resolveChainedSynonyms(out []specsRow) {
	nonSynCodes := map[string]bool{}
	synTarget := map[string]string{}
	for _, r := range out {
		if r.Code != nil && *r.Code != "" && !strings.EqualFold(strVal(r.Codetype), "S") {
			nonSynCodes[strings.ToUpper(*r.Code)] = true
		}
		if strings.EqualFold(strVal(r.Codetype), "S") && r.OldCode != nil && r.Code != nil && !strings.EqualFold(*r.OldCode, *r.Code) {
			synTarget[strings.ToUpper(*r.OldCode)] = *r.Code
		}
	}
	for i := range out {
		if !strings.EqualFold(strVal(out[i].Codetype), "S") || out[i].Code == nil {
			continue
		}
		cur := *out[i].Code
		for hop := 0; hop < 4 && !nonSynCodes[strings.ToUpper(cur)]; hop++ {
			next, ok := synTarget[strings.ToUpper(cur)]
			if !ok || strings.EqualFold(next, cur) {
				break
			}
			cur = next
		}
		if cur != *out[i].Code {
			curCopy := cur
			out[i].Code = &curCopy
		}
	}
}

func propagateGenusAndCodeFamilies(out []specsRow, genusFamily map[string][2]*string) {
	for pass := 0; pass < 3; pass++ {
		codeFamily := collectCodeAndGenusFamilies(out, genusFamily)
		backfillMissingFamilies(out, codeFamily, genusFamily)
	}
}

func collectCodeAndGenusFamilies(out []specsRow, genusFamily map[string][2]*string) map[string][2]*string {
	codeFamily := map[string][2]*string{}
	for _, r := range out {
		if r.FamilyCode == nil || *r.FamilyCode == "" {
			continue
		}
		if r.Code != nil && *r.Code != "" {
			cu := strings.ToUpper(*r.Code)
			if _, seen := codeFamily[cu]; !seen {
				codeFamily[cu] = [2]*string{r.APCFamily, r.FamilyCode}
			}
		}
		if r.ScientificName != nil && *r.ScientificName != "" {
			if gk := genusKey(*r.ScientificName); gk != "" {
				if _, seen := genusFamily[gk]; !seen {
					genusFamily[gk] = [2]*string{r.APCFamily, r.FamilyCode}
				}
			}
		}
	}
	return codeFamily
}

func backfillMissingFamilies(out []specsRow, codeFamily, genusFamily map[string][2]*string) {
	for i := range out {
		if (out[i].FamilyCode == nil || *out[i].FamilyCode == "") && out[i].Code != nil {
			if fam, ok := codeFamily[strings.ToUpper(*out[i].Code)]; ok {
				if out[i].APCFamily == nil {
					out[i].APCFamily = fam[0]
				}
				out[i].FamilyCode = fam[1]
			}
		}
		if (out[i].FamilyCode == nil || *out[i].FamilyCode == "") && out[i].ScientificName != nil {
			if fam, ok := genusFamily[genusKey(*out[i].ScientificName)]; ok {
				if out[i].APCFamily == nil {
					out[i].APCFamily = fam[0]
				}
				out[i].FamilyCode = fam[1]
			}
		}
	}
}

func ensureLMH25TreeCodeAcx(out []specsRow, nextID *int64) []specsRow {
	for _, r := range out {
		if strings.EqualFold(strVal(r.TreeCode), "Acx") || strings.EqualFold(strVal(r.Code), "POPUHAS") {
			return out
		}
	}
	idVal := *nextID
	*nextID++
	yoc, chg := "2023", "LMH25 (2023) Sec 9.24 Version 2022 tree code addition"
	fam, code, tc, sci := "SALICAC", "POPUHAS", "Acx", "Populus x hastata"
	lf, cl, repOne := int64(2), int64(7), int64(1)
	auth, eng, nat, ct, tl, provBC := "Dode", "black x balsam poplar hybrid", "N", "U", "hyb", "BC"
	return append(out, specsRow{
		YearOfChange: &yoc, ChangeDescription: &chg, APCFamily: &fam, FamilyCode: &fam,
		OldCode: &code, Code: &code, SplCode: &code, TreeCode: &tc, ScientificName: &sci,
		Lifeform: &lf, Authority: &auth, EnglishName: &eng, Native: &nat, Codetype: &ct,
		Province: &provBC, ID: &idVal, TaxonLevel: &tl, IsAttribute: 0, Report: &repOne,
		SplCodeCalc: &code, Codelength: &cl,
	})
}

func sortMergedSpecsRows(out []specsRow) {
	sort.SliceStable(out, func(i, j int) bool {
		ci, cj := strings.ToUpper(strVal(out[i].Code)), strings.ToUpper(strVal(out[j].Code))
		if ci != cj {
			return ci < cj
		}
		oi, oj := strings.ToUpper(strVal(out[i].OldCode)), strings.ToUpper(strVal(out[j].OldCode))
		if oi != oj {
			return oi < oj
		}
		return normSciKey(strVal(out[i].ScientificName)) < normSciKey(strVal(out[j].ScientificName))
	})
}
