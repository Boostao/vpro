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

func deriveBECSynonymOldCode(sci string, targetCode string, usedOldCodes map[string]bool) string {
	fields := strings.Fields(sci)
	if len(fields) == 0 {
		return strings.ToUpper(targetCode)
	}
	lettersOnly := func(s string) string {
		var b strings.Builder
		for _, r := range s {
			if unicode.IsLetter(r) {
				b.WriteRune(unicode.ToUpper(r))
			}
		}
		return b.String()
	}
	genus := lettersOnly(fields[0])
	if len(genus) > 4 {
		genus = genus[:4]
	}
	species := ""
	if len(fields) >= 2 {
		ep := fields[1]
		if strings.EqualFold(ep, "x") && len(fields) >= 3 {
			species = "X" + lettersOnly(fields[2])
		} else {
			species = lettersOnly(ep)
		}
	}
	if len(species) > 3 {
		species = species[:3]
	}
	base := genus + species
	if base == "" {
		base = strings.ToUpper(targetCode)
	}
	// Check if infraspecific (ssp. / subsp. / var.)
	isInfra := false
	for _, f := range fields {
		lf := strings.ToLower(strings.TrimSuffix(f, "."))
		if lf == "ssp" || lf == "subsp" || lf == "var" {
			isInfra = true
			break
		}
	}
	if !isInfra && !strings.EqualFold(base, targetCode) && !usedOldCodes[base] {
		return base
	}
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
	// Load historical USysAllSpecs (excluding newly minted 19000001+ IDs so re-runs are 100% idempotent!)
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
	var hist []specsRow
	byCodeNonSyn := map[string]int{}
	bySci := map[string][]int{}
	genusFamily := map[string][2]*string{} // full lowercase genus word -> [APCFamily, FamilyCode]
	usedOldCodes := map[string]bool{}

	for rows.Next() {
		var r specsRow
		if err := rows.Scan(
			&r.YearOfChange, &r.ChangeDescription, &r.APCFamily, &r.FamilyCode, &r.OldCode, &r.Code, &r.SplCode, &r.TreeCode,
			&r.ScientificName, &r.Lifeform, &r.Authority, &r.EnglishNameOld, &r.EnglishName, &r.CommonNamePB,
			&r.NotesOnNames, &r.ShortenedGuideName, &r.Native, &r.Codetype, &r.Province, &r.ID, &r.TaxonLevel,
			&r.IsAttribute, &r.Report, &r.SplCodeCalc, &r.Codelength, &r.CombinedEnglishName,
		); err != nil {
			rows.Close()
			return nil, err
		}
		if r.ID != nil && *r.ID >= 19000001 {
			continue
		}
		idx := len(hist)
		hist = append(hist, r)
		if r.OldCode != nil && *r.OldCode != "" {
			usedOldCodes[strings.ToUpper(*r.OldCode)] = true
		}
		if r.Code != nil && *r.Code != "" && !strings.EqualFold(strVal(r.Codetype), "S") {
			cu := strings.ToUpper(*r.Code)
			if prevIdx, seen := byCodeNonSyn[cu]; !seen || (!strings.EqualFold(strVal(hist[prevIdx].Codetype), "U") && strings.EqualFold(strVal(r.Codetype), "U")) {
				byCodeNonSyn[cu] = idx
			}
		}
		if r.ScientificName != nil && *r.ScientificName != "" {
			sk := normSciKey(*r.ScientificName)
			bySci[sk] = append(bySci[sk], idx)
			if gk := genusKey(*r.ScientificName); gk != "" && r.APCFamily != nil && r.FamilyCode != nil {
				if _, ok := genusFamily[gk]; !ok {
					genusFamily[gk] = [2]*string{r.APCFamily, r.FamilyCode}
				}
			}
		}
	}
	rows.Close()

	_, taxa2025, err := taxaAccdb.ReadAll("USysAllSpecs")
	if err != nil {
		return nil, err
	}

	consumedHist := make([]bool, len(hist))
	var out []specsRow
	nextID := int64(19000001)
	provBC := "BC"
	repOne := int64(1)
	repZero := int64(0)

	// Pass 1: Process all non-synonym (accepted / excluded / extra) 2025 rows first so they deterministically claim their Code rows.
	for _, tr := range taxa2025 {
		ct := optStr(tr[8])
		if strings.EqualFold(strVal(ct), "S") {
			continue
		}
		yoc := optStr(tr[0])
		chg := optStr(tr[1])
		sci := optStr(tr[2])
		eng := optStr(tr[3])
		short := optStr(tr[4])
		code := optStr(tr[5])
		spl := optStr(tr[6])
		nat := optStr(tr[7])
		taxLvl := optStr(tr[9])
		var lf *int64
		if v, ok := tr[10].(int64); ok {
			vc := v
			lf = &vc
		}
		tree := optStr(tr[11])
		isAttr := int64(0)
		if b, ok := tr[12].(bool); ok && b {
			isAttr = -1
		}

		cu := strings.ToUpper(strVal(code))
		matchedIdx := -1
		if sci != nil {
			for _, candIdx := range bySci[normSciKey(*sci)] {
				if !consumedHist[candIdx] && !strings.EqualFold(strVal(hist[candIdx].Codetype), "S") && strings.EqualFold(strVal(hist[candIdx].Code), cu) {
					matchedIdx = candIdx
					break
				}
			}
		}
		if matchedIdx < 0 {
			if idx, ok := byCodeNonSyn[cu]; ok && !consumedHist[idx] {
				matchedIdx = idx
			}
		}
		if matchedIdx >= 0 {
			consumedHist[matchedIdx] = true
			base := hist[matchedIdx]
			if yoc != nil {
				base.YearOfChange = yoc
			}
			if chg != nil {
				base.ChangeDescription = chg
			}
			base.ScientificName = sci
			if eng != nil {
				base.EnglishName = eng
			}
			if short != nil {
				base.ShortenedGuideName = short
			}
			base.Code = code
			if base.OldCode == nil || strings.EqualFold(*base.OldCode, cu) {
				base.OldCode = code
			}
			base.SplCode = spl
			if nat != nil {
				base.Native = nat
			}
			base.Codetype = ct
			if taxLvl != nil {
				base.TaxonLevel = taxLvl
			}
			if lf != nil {
				base.Lifeform = lf
			}
			if tree != nil {
				base.TreeCode = tree
			}
			base.IsAttribute = isAttr
			out = append(out, base)
		} else {
			idVal := nextID
			nextID++
			var apcFam, famCode *string
			if gk := genusKey(strVal(sci)); gk != "" {
				if fam, ok := genusFamily[gk]; ok {
					apcFam, famCode = fam[0], fam[1]
				}
			}
			cl := int64(len(strVal(code)))
			out = append(out, specsRow{
				YearOfChange:       yoc,
				ChangeDescription:  chg,
				APCFamily:          apcFam,
				FamilyCode:         famCode,
				OldCode:            code,
				Code:               code,
				SplCode:            spl,
				TreeCode:           tree,
				ScientificName:     sci,
				Lifeform:           lf,
				EnglishName:        eng,
				ShortenedGuideName: short,
				Native:             nat,
				Codetype:           ct,
				Province:           &provBC,
				ID:                 &idVal,
				TaxonLevel:         taxLvl,
				IsAttribute:        isAttr,
				Report:             &repOne,
				SplCodeCalc:        spl,
				Codelength:         &cl,
			})
		}
	}

	// Pass 2: Process all synonym (Codetype == 'S') 2025 rows against remaining unconsumed historical rows.
	for _, tr := range taxa2025 {
		ct := optStr(tr[8])
		if !strings.EqualFold(strVal(ct), "S") {
			continue
		}
		yoc := optStr(tr[0])
		chg := optStr(tr[1])
		sci := optStr(tr[2])
		eng := optStr(tr[3])
		short := optStr(tr[4])
		code := optStr(tr[5])
		spl := optStr(tr[6])
		nat := optStr(tr[7])
		taxLvl := optStr(tr[9])
		var lf *int64
		if v, ok := tr[10].(int64); ok {
			vc := v
			lf = &vc
		}
		tree := optStr(tr[11])
		isAttr := int64(0)
		if b, ok := tr[12].(bool); ok && b {
			isAttr = -1
		}

		sk := normSciKey(strVal(sci))
		matchedIdx := -1
		for _, candIdx := range bySci[sk] {
			if !consumedHist[candIdx] {
				matchedIdx = candIdx
				break
			}
		}
		if matchedIdx >= 0 {
			consumedHist[matchedIdx] = true
			base := hist[matchedIdx]
			if yoc != nil {
				base.YearOfChange = yoc
			}
			if chg != nil {
				base.ChangeDescription = chg
			}
			base.ScientificName = sci
			if eng != nil {
				base.EnglishName = eng
			}
			if short != nil {
				base.ShortenedGuideName = short
			}
			base.Code = code
			base.SplCode = spl
			if nat != nil {
				base.Native = nat
			}
			base.Codetype = ct
			if taxLvl != nil {
				base.TaxonLevel = taxLvl
			}
			if lf != nil {
				base.Lifeform = lf
			}
			if tree != nil {
				base.TreeCode = tree
			}
			base.IsAttribute = isAttr
			if base.OldCode == nil || *base.OldCode == "" {
				oc := deriveBECSynonymOldCode(strVal(sci), strVal(code), usedOldCodes)
				usedOldCodes[oc] = true
				base.OldCode = &oc
			}
			out = append(out, base)
		} else {
			idVal := nextID
			nextID++
			oc := deriveBECSynonymOldCode(strVal(sci), strVal(code), usedOldCodes)
			usedOldCodes[oc] = true
			var apcFam, famCode *string
			if gk := genusKey(strVal(sci)); gk != "" {
				if fam, ok := genusFamily[gk]; ok {
					apcFam, famCode = fam[0], fam[1]
				}
			}
			cl := int64(len(oc))
			out = append(out, specsRow{
				YearOfChange:       yoc,
				ChangeDescription:  chg,
				APCFamily:          apcFam,
				FamilyCode:         famCode,
				OldCode:            &oc,
				Code:               code,
				SplCode:            spl,
				TreeCode:           tree,
				ScientificName:     sci,
				Lifeform:           lf,
				EnglishName:        eng,
				ShortenedGuideName: short,
				Native:             nat,
				Codetype:           ct,
				Province:           &provBC,
				ID:                 &idVal,
				TaxonLevel:         taxLvl,
				IsAttribute:        isAttr,
				Report:             &repZero,
				SplCodeCalc:        spl,
				Codelength:         &cl,
			})
		}
	}

	// Retain all unconsumed historical rows so ZERO OldCode -> Code synonyms or historical codes are lost!
	for i, hr := range hist {
		if consumedHist[i] {
			continue
		}
		out = append(out, hr)
	}

	// Resolve chained synonyms (e.g., CUPRNOO -> XANTNOO -> CALLNOO) where intermediate Code has no accepted/non-synonym row
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
		if strings.EqualFold(strVal(out[i].Codetype), "S") && out[i].Code != nil {
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

	// Enrich newly-split genera (e.g., Mitella -> Brewerimitella, Thelypteris -> Amauropelta/Oreopteris) to fixed point
	for pass := 0; pass < 3; pass++ {
		codeFamily := map[string][2]*string{}
		for _, r := range out {
			if r.Code != nil && *r.Code != "" && r.FamilyCode != nil && *r.FamilyCode != "" {
				cu := strings.ToUpper(*r.Code)
				if _, seen := codeFamily[cu]; !seen {
					codeFamily[cu] = [2]*string{r.APCFamily, r.FamilyCode}
				}
			}
			if r.ScientificName != nil && *r.ScientificName != "" && r.FamilyCode != nil && *r.FamilyCode != "" {
				if gk := genusKey(*r.ScientificName); gk != "" {
					if _, seen := genusFamily[gk]; !seen {
						genusFamily[gk] = [2]*string{r.APCFamily, r.FamilyCode}
					}
				}
			}
		}
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

	// Ensure LMH25 (2023) Section 9.24 Version 2022 Tree Code Acx (Populus x hastata, black x balsam poplar hybrid) is present
	hasAcx := false
	for _, r := range out {
		if strings.EqualFold(strVal(r.TreeCode), "Acx") || strings.EqualFold(strVal(r.Code), "POPUHAS") {
			hasAcx = true
			break
		}
	}
	if !hasAcx {
		idVal := nextID
		nextID++
		yoc, chg := "2023", "LMH25 (2023) Sec 9.24 Version 2022 tree code addition"
		fam := "SALICAC"
		code := "POPUHAS"
		tc := "Acx"
		sci := "Populus x hastata"
		lf := int64(2)
		auth := "Dode"
		eng := "black x balsam poplar hybrid"
		nat := "N"
		ct := "U"
		tl := "hyb"
		cl := int64(7)
		out = append(out, specsRow{
			YearOfChange:      &yoc,
			ChangeDescription: &chg,
			APCFamily:         &fam,
			FamilyCode:        &fam,
			OldCode:           &code,
			Code:              &code,
			SplCode:           &code,
			TreeCode:          &tc,
			ScientificName:    &sci,
			Lifeform:          &lf,
			Authority:         &auth,
			EnglishName:       &eng,
			Native:            &nat,
			Codetype:          &ct,
			Province:          &provBC,
			ID:                &idVal,
			TaxonLevel:        &tl,
			IsAttribute:       0,
			Report:            &repOne,
			SplCodeCalc:       &code,
			Codelength:        &cl,
		})
	}

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
	return out, nil
}
