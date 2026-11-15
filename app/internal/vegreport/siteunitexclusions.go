package vegreport

import (
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// DefaultSiteUnitExclusionPatterns returns the BEC standard excluded SiteUnit suffixes
// per VPro2.0_Functions pp. 12-13 (P054, P060).
func DefaultSiteUnitExclusionPatterns() []string {
	return []string{".support", ".poor", ".nudum"}
}

type SiteUnitExclusionRule struct {
	Pattern   string `json:"pattern"`
	MatchMode string `json:"matchMode"` // "auto" (default) | "suffix" | "contains" | "wildcard"
	Enabled   bool   `json:"enabled"`
}

func (r *SiteUnitExclusionRule) UnmarshalJSON(data []byte) error {
	type plain SiteUnitExclusionRule
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type ExcludedSiteUnitInfo struct {
	SiteUnit       string `json:"siteUnit"`
	MatchedPattern string `json:"matchedPattern"`
	PlotCount      int    `json:"plotCount"`
}

type RetainedSiteUnitInfo struct {
	SiteUnit  string `json:"siteUnit"`
	PlotCount int    `json:"plotCount"`
}

type SiteUnitExclusionSummary struct {
	AppliedRules     []SiteUnitExclusionRule `json:"appliedRules"`
	TotalPlotsBefore int                     `json:"totalPlotsBefore"`
	RetainedPlots    int                     `json:"retainedPlots"`
	ExcludedPlots    int                     `json:"excludedPlots"`
	RetainedUnits    []RetainedSiteUnitInfo  `json:"retainedUnits"`
	ExcludedUnits    []ExcludedSiteUnitInfo  `json:"excludedUnits"`
}

type HierarchyBreakpointOptions struct {
	BreakpointPolicy   string `json:"breakpointPolicy"`   // "lowest" (default) | "highest"
	UnbrokenUnitPolicy string `json:"unbrokenUnitPolicy"` // "keep_original" (default) | "exclude_unbroken"
	StripTildePrefix   bool   `json:"stripTildePrefix"`
}

func (r *HierarchyBreakpointOptions) UnmarshalJSON(data []byte) error {
	type plain HierarchyBreakpointOptions
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type HierarchyBreakpointUnitMapping struct {
	OriginalUnit  string `json:"originalUnit"`
	EffectiveUnit string `json:"effectiveUnit"`
	RolledUp      bool   `json:"rolledUp"`
	MatchedInTree bool   `json:"matchedInTree"`
	Excluded      bool   `json:"excluded"`
	PlotCount     int    `json:"plotCount"`
}

type HierarchyBreakpointBucket struct {
	BreakpointUnit string   `json:"breakpointUnit"`
	SourceUnits    []string `json:"sourceUnits"`
	PlotCount      int      `json:"plotCount"`
}

type HierarchyBreakpointResolution struct {
	ContextID         string                           `json:"contextId"`
	Project           string                           `json:"project"`
	SU                string                           `json:"su"`
	Hierarchy         string                           `json:"hierarchy"`
	BreakpointPolicy  string                           `json:"breakpointPolicy"`
	TotalUnitsBefore  int                              `json:"totalUnitsBefore"`
	TotalUnitsAfter   int                              `json:"totalUnitsAfter"`
	RolledUpPlotCount int                              `json:"rolledUpPlotCount"`
	UnmappedUnits     []string                         `json:"unmappedUnits"`
	Mappings          []HierarchyBreakpointUnitMapping `json:"mappings"`
	Buckets           []HierarchyBreakpointBucket      `json:"buckets"`
}

type HierarchyBreakpointRequest struct {
	Rules             []SiteUnitExclusionRule    `json:"rules"`
	UseDefaultPresets bool                       `json:"useDefaultPresets"`
	Options           HierarchyBreakpointOptions `json:"options"`
}

func (r *HierarchyBreakpointRequest) UnmarshalJSON(data []byte) error {
	type plain HierarchyBreakpointRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SiteUnitExclusionPreviewRequest struct {
	Rules                   []SiteUnitExclusionRule    `json:"rules"`
	UseDefaultPresets       bool                       `json:"useDefaultPresets"`
	UseHierarchyBreakpoints bool                       `json:"useHierarchyBreakpoints"`
	BreakpointOptions       HierarchyBreakpointOptions `json:"breakpointOptions"`
}

func (r *SiteUnitExclusionPreviewRequest) UnmarshalJSON(data []byte) error {
	type plain SiteUnitExclusionPreviewRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SiteUnitExclusionPreview struct {
	ContextID   string                         `json:"contextId"`
	Project     string                         `json:"project"`
	SU          string                         `json:"su"`
	Hierarchy   string                         `json:"hierarchy"`
	Exclusions  SiteUnitExclusionSummary       `json:"exclusions"`
	Breakpoints *HierarchyBreakpointResolution `json:"breakpoints,omitempty"`
}

type SummaryVegetationExclusionRequest struct {
	Average                 int                                `json:"average"`
	Display                 int                                `json:"display"`
	ShowClass               int                                `json:"showClass"`
	GroupAndOrder           int                                `json:"groupAndOrder"`
	Rules                   []SiteUnitExclusionRule            `json:"rules"`
	UseDefaultPresets       bool                               `json:"useDefaultPresets"`
	UseHierarchyBreakpoints bool                               `json:"useHierarchyBreakpoints"`
	BreakpointOptions       HierarchyBreakpointOptions         `json:"breakpointOptions"`
	References              *SummaryVegetationReferenceOptions `json:"references,omitempty"`
}

func (r *SummaryVegetationExclusionRequest) UnmarshalJSON(data []byte) error {
	type plain SummaryVegetationExclusionRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SummaryVegetationExclusionPreview struct {
	Preview     SummaryVegetationPreview       `json:"preview"`
	Exclusions  SiteUnitExclusionSummary       `json:"exclusions"`
	Breakpoints *HierarchyBreakpointResolution `json:"breakpoints,omitempty"`
}

type LongVegetationExclusionRequest struct {
	Rules                   []SiteUnitExclusionRule    `json:"rules"`
	UseDefaultPresets       bool                       `json:"useDefaultPresets"`
	UseHierarchyBreakpoints bool                       `json:"useHierarchyBreakpoints"`
	BreakpointOptions       HierarchyBreakpointOptions `json:"breakpointOptions"`
}

func (r *LongVegetationExclusionRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationExclusionRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type LongVegetationExclusionPreview struct {
	Preview     LongVegetationPreview          `json:"preview"`
	Exclusions  SiteUnitExclusionSummary       `json:"exclusions"`
	Breakpoints *HierarchyBreakpointResolution `json:"breakpoints,omitempty"`
}

func NormalizeExclusionRules(rules []SiteUnitExclusionRule, useDefaults bool) ([]SiteUnitExclusionRule, error) {
	if len(rules) == 0 && useDefaults {
		defaults := DefaultSiteUnitExclusionPatterns()
		out := make([]SiteUnitExclusionRule, len(defaults))
		for i, p := range defaults {
			out[i] = SiteUnitExclusionRule{Pattern: p, MatchMode: "auto", Enabled: true}
		}
		return out, nil
	}
	out := make([]SiteUnitExclusionRule, 0, len(rules))
	for _, r := range rules {
		if !utf8.ValidString(r.Pattern) || strings.ContainsRune(r.Pattern, 0) {
			return nil, fmt.Errorf("SiteUnit exclusion pattern %q must be valid UTF-8 without NUL", r.Pattern)
		}
		p := strings.TrimSpace(r.Pattern)
		if p == "" {
			continue
		}
		mode := strings.ToLower(strings.TrimSpace(r.MatchMode))
		if mode == "" {
			mode = "auto"
		}
		if mode != "auto" && mode != "suffix" && mode != "contains" && mode != "wildcard" {
			return nil, fmt.Errorf("unsupported SiteUnit exclusion matchMode %q", r.MatchMode)
		}
		out = append(out, SiteUnitExclusionRule{
			Pattern:   p,
			MatchMode: mode,
			Enabled:   r.Enabled,
		})
	}
	return out, nil
}

// wildcardCaseInsensitiveMatch matches '*' (zero or more runes) and '?' (single rune) on lowercased runes.
func wildcardCaseInsensitiveMatch(pattern, target string) bool {
	p := []rune(strings.ToLower(pattern))
	s := []rune(strings.ToLower(target))
	pi, si := 0, 0
	starIdx, matchIdx := -1, 0
	for si < len(s) {
		if pi < len(p) && (p[pi] == '?' || p[pi] == s[si]) {
			pi++
			si++
		} else if pi < len(p) && p[pi] == '*' {
			starIdx = pi
			matchIdx = si
			pi++
		} else if starIdx != -1 {
			pi = starIdx + 1
			matchIdx++
			si = matchIdx
		} else {
			return false
		}
	}
	for pi < len(p) && p[pi] == '*' {
		pi++
	}
	return pi == len(p)
}

func MatchSiteUnitExclusion(siteUnit string, rules []SiteUnitExclusionRule) (bool, string) {
	trimmedUnit := strings.TrimSpace(siteUnit)
	if trimmedUnit == "" {
		return false, ""
	}
	lowerUnit := strings.ToLower(trimmedUnit)

	for _, rule := range rules {
		if !rule.Enabled {
			continue
		}
		pat := strings.TrimSpace(rule.Pattern)
		if pat == "" {
			continue
		}
		lowerPat := strings.ToLower(pat)
		mode := rule.MatchMode
		if mode == "" || mode == "auto" {
			if strings.ContainsAny(pat, "*?") {
				mode = "wildcard"
			} else if strings.HasPrefix(pat, ".") {
				// Dot-prefixed BEC unit qualifier (e.g. .support, .poor, .nudum):
				// match suffix OR dot-delimited segment (e.g. CWHvm1/01.support-a, CWHvm1/01.poor.1).
				if strings.HasSuffix(lowerUnit, lowerPat) ||
					strings.Contains(lowerUnit, lowerPat+".") ||
					strings.Contains(lowerUnit, lowerPat+"-") ||
					strings.Contains(lowerUnit, lowerPat+"_") ||
					strings.Contains(lowerUnit, lowerPat+" ") {
					return true, rule.Pattern
				}
				continue
			} else {
				mode = "contains"
			}
		}

		switch mode {
		case "suffix":
			if strings.HasSuffix(lowerUnit, lowerPat) {
				return true, rule.Pattern
			}
		case "contains":
			if strings.Contains(lowerUnit, lowerPat) {
				return true, rule.Pattern
			}
		case "wildcard":
			if wildcardCaseInsensitiveMatch(lowerPat, lowerUnit) {
				return true, rule.Pattern
			}
		}
	}
	return false, ""
}

func FilterSUTableByExclusions(
	su vprocore.ProjectMetadataTable,
	rules []SiteUnitExclusionRule,
) (vprocore.ProjectMetadataTable, SiteUnitExclusionSummary, error) {
	sc, err := vprocore.SiteUnitTransferColumns(su, "PlotNumber", "SiteUnit")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, SiteUnitExclusionSummary{}, err
	}
	filtered := vprocore.ProjectMetadataTable{
		Columns: append([]vprocore.ProjectMetadataColumn{}, su.Columns...),
		Rows:    make([]vprocore.ProjectMetadataRow, 0, len(su.Rows)),
	}
	summary := SiteUnitExclusionSummary{
		AppliedRules:  append([]SiteUnitExclusionRule{}, rules...),
		RetainedUnits: []RetainedSiteUnitInfo{},
		ExcludedUnits: []ExcludedSiteUnitInfo{},
	}

	type excludedBucket struct {
		unit    string
		pattern string
		count   int
	}
	excludedByUnit := map[string]*excludedBucket{}
	retainedByUnit := map[string]int{}

	for _, row := range su.Rows {
		plotCell := row.Cells[sc["PlotNumber"]]
		unitCell := row.Cells[sc["SiteUnit"]]
		hasPlot := plotCell.Storage == "text" && plotCell.Text != nil && strings.TrimSpace(*plotCell.Text) != ""
		unitStr := ""
		if unitCell.Storage == "text" && unitCell.Text != nil {
			unitStr = *unitCell.Text
		}
		if hasPlot && strings.TrimSpace(unitStr) != "" {
			summary.TotalPlotsBefore++
		}

		if strings.TrimSpace(unitStr) != "" {
			if excluded, matchedPat := MatchSiteUnitExclusion(unitStr, rules); excluded {
				if hasPlot {
					summary.ExcludedPlots++
				}
				b := excludedByUnit[unitStr]
				if b == nil {
					b = &excludedBucket{unit: unitStr, pattern: matchedPat}
					excludedByUnit[unitStr] = b
				}
				if hasPlot {
					b.count++
				}
				continue
			}
		}

		if hasPlot && strings.TrimSpace(unitStr) != "" {
			summary.RetainedPlots++
			retainedByUnit[unitStr]++
		}
		clonedCells := make([]vprocore.ProjectMetadataCell, len(row.Cells))
		for i, c := range row.Cells {
			clonedCells[i] = vprocore.CloneSiteUnitCell(c)
		}
		filtered.Rows = append(filtered.Rows, vprocore.ProjectMetadataRow{
			RowID: row.RowID,
			Cells: clonedCells,
		})
	}

	retKeys := make([]string, 0, len(retainedByUnit))
	for k := range retainedByUnit {
		retKeys = append(retKeys, k)
	}
	slices.Sort(retKeys)
	for _, k := range retKeys {
		summary.RetainedUnits = append(summary.RetainedUnits, RetainedSiteUnitInfo{
			SiteUnit:  k,
			PlotCount: retainedByUnit[k],
		})
	}

	excKeys := make([]string, 0, len(excludedByUnit))
	for k := range excludedByUnit {
		excKeys = append(excKeys, k)
	}
	slices.Sort(excKeys)
	for _, k := range excKeys {
		b := excludedByUnit[k]
		summary.ExcludedUnits = append(summary.ExcludedUnits, ExcludedSiteUnitInfo{
			SiteUnit:       b.unit,
			MatchedPattern: b.pattern,
			PlotCount:      b.count,
		})
	}

	return filtered, summary, nil
}
