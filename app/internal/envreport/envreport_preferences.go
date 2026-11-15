package envreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func validateLongEnvironmentTitle(title string) error {
	if !utf8.ValidString(title) || strings.ContainsRune(title, 0) {
		return errors.New("Long Environment title requires complete Unicode without NUL; no repair or normalization")
	}
	return nil
}

func ReadLongEnvironmentPreference(s *vprocore.DesktopConfig, ctx context.Context) (string, error) {
	if ctx == nil {
		return "", errors.New("Long Environment preferences require a context")
	}
	if s == nil {
		return "", errors.New("Long Environment preference configuration is unavailable")
	}
	if err := sqlutil.AcquireMutexLease(ctx, &s.Mu); err != nil {
		return "", err
	}
	defer s.Mu.Unlock()
	values, err := s.ReadLocked()
	if err != nil {
		return "", err
	}
	title, err := vprocore.ConfigString(values, "ReportOptions", "LEReportTitle")
	if err != nil {
		return "", err
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return title, nil
}

func CompareAndSetLongEnvironmentPreference(s *vprocore.DesktopConfig, ctx context.Context, expected, proposed string) (vprocore.ConfigStringPreferenceUpdate, error) {
	if ctx == nil {
		return vprocore.ConfigStringPreferenceUpdate{}, errors.New("Long Environment preference changes require a context")
	}
	if s == nil {
		return vprocore.ConfigStringPreferenceUpdate{}, errors.New("Long Environment preference configuration is unavailable")
	}
	if expected != proposed {
		if err := validateLongEnvironmentTitle(proposed); err != nil {
			return vprocore.ConfigStringPreferenceUpdate{}, err
		}
	}
	return s.CompareAndSetReportStrings(ctx, "Long Environment preferences", []vprocore.ReportStringPreferenceChange{
		{Key: "LEReportTitle", Expected: expected, Proposed: proposed},
	})
}

type LongEnvironmentPreferenceValues struct {
	Title string `json:"title"`
}

func (v *LongEnvironmentPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongEnvironmentPreferenceValues
	var decoded plain
	if err := vprocore.DecodeGoogleEarthKMLJSON(data, &decoded, "Long Environment preferences", "title"); err != nil {
		return err
	}
	*v = LongEnvironmentPreferenceValues(decoded)
	return nil
}

type LongEnvironmentPreferencesRequest struct {
	Expected LongEnvironmentPreferenceValues `json:"expected"`
	Proposed LongEnvironmentPreferenceValues `json:"proposed"`
}

func (v *LongEnvironmentPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongEnvironmentPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeGoogleEarthKMLJSON(data, &decoded, "Long Environment preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongEnvironmentPreferencesRequest(decoded)
	return nil
}

type LongEnvironmentPreferencesReview struct {
	ContextID   string                          `json:"contextId"`
	Project     string                          `json:"project"`
	ProjectPath string                          `json:"projectPath"`
	SU          string                          `json:"su"`
	SUPath      string                          `json:"suPath"`
	Values      LongEnvironmentPreferenceValues `json:"values"`
}

type LongEnvironmentPreferencesOutcome struct {
	ContextID    string `json:"contextId"`
	Changed      bool   `json:"changed"`
	Committed    bool   `json:"committed"`
	ErrorMessage string `json:"errorMessage"`
}

type LongEnvironmentPreferencesService struct {
	contexts *vprocore.ContextService
	snapshot vprocore.PublicationReadSnapshotHooks
}

func NewLongEnvironmentPreferencesService(contexts *vprocore.ContextService) *LongEnvironmentPreferencesService {
	return &LongEnvironmentPreferencesService{contexts: contexts}
}

func (s *LongEnvironmentPreferencesService) helper() vprocore.ReportPreferenceHelper {
	if s == nil {
		return vprocore.ReportPreferenceHelper{}
	}
	return vprocore.ReportPreferenceHelper{Contexts: s.contexts, Snapshot: s.snapshot}
}

func (s *LongEnvironmentPreferencesService) GetLongEnvironmentPreferences(ctx context.Context, contextID string) (*LongEnvironmentPreferencesReview, error) {
	return vprocore.GetOwnedReportPreferences(ctx, s.helper(), contextID, "Long Environment",
		func(plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongEnvironmentPreferencesReview, error) {
			title, err := ReadLongEnvironmentPreference(plots.Projects.Preferences, ctx)
			if err != nil {
				return nil, err
			}
			if err := vprocore.ValidateGoogleEarthReviewStrings(title); err != nil {
				return nil, err
			}
			return &LongEnvironmentPreferencesReview{
				ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
				SU: owner.Selection.SU, SUPath: owner.Selection.SUPath,
				Values: LongEnvironmentPreferenceValues{Title: title},
			}, nil
		})
}

func (s *LongEnvironmentPreferencesService) SaveLongEnvironmentPreferences(ctx context.Context, contextID, requestJSON string) *LongEnvironmentPreferencesOutcome {
	out := LongEnvironmentPreferencesOutcome(vprocore.SaveOwnedReportPreferences(ctx, s.helper(), contextID, requestJSON, "Long Environment", nil,
		func(plots *vprocore.PlotService, request LongEnvironmentPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
			return CompareAndSetLongEnvironmentPreference(plots.Projects.Preferences, ctx, request.Expected.Title, request.Proposed.Title)
		}))
	return &out
}

type SiteUnitSummaryPreferenceValues struct {
	Method       int `json:"method"`
	SiteUnitType int `json:"siteUnitType"`
}

func (values *SiteUnitSummaryPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain SiteUnitSummaryPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Summary Environment preferences", "method", "siteUnitType"); err != nil {
		return err
	}
	*values = SiteUnitSummaryPreferenceValues(decoded)
	return nil
}

func CompareAndSetSiteUnitSummaryPreferences(s *vprocore.DesktopConfig, ctx context.Context,
	expected, proposed SiteUnitSummaryPreferenceValues) (vprocore.ReportPreferenceUpdate, error) {
	if proposed.Method != 1 && proposed.Method != 2 {
		return vprocore.ReportPreferenceUpdate{}, errors.New("Summary Environment requires Mean (1) or Interquartile (2)")
	}
	if proposed.SiteUnitType < 1 || proposed.SiteUnitType > 3 {
		return vprocore.ReportPreferenceUpdate{}, errors.New("Summary Environment requires Normal SU (1), Hierarchy Breakpoints (2), or Field-Derived (3)")
	}
	return vprocore.CompareAndSetReportPreferences(s, ctx, "Summary Environment preferences", []vprocore.ReportPreferenceChange[int]{
		{Key: "SEOptValueMethod", Expected: expected.Method, Proposed: proposed.Method},
		{Key: "SESuType", Expected: expected.SiteUnitType, Proposed: proposed.SiteUnitType},
	}, func(values vprocore.ConfigValues, key string) (int, error) {
		switch key {
		case "SEOptValueMethod":
			return vprocore.ConfigInt(values, "ReportOptions", key, 1, 2)
		case "SESuType":
			return vprocore.ConfigInt(values, "ReportOptions", key, 1, 3)
		default:
			return 0, fmt.Errorf("unsupported Summary Environment preference %s", key)
		}
	})
}

type SiteUnitSummaryPreferencesRequest struct {
	Expected SiteUnitSummaryPreferenceValues `json:"expected"`
	Proposed SiteUnitSummaryPreferenceValues `json:"proposed"`
}

func (request *SiteUnitSummaryPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain SiteUnitSummaryPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Summary Environment preference save", "expected", "proposed"); err != nil {
		return err
	}
	*request = SiteUnitSummaryPreferencesRequest(decoded)
	return nil
}

type SiteUnitSummaryPreferencesOutcome struct {
	ContextID    string `json:"contextId"`
	Changed      bool   `json:"changed"`
	Committed    bool   `json:"committed"`
	ErrorMessage string `json:"errorMessage"`
}

type SiteUnitSummaryPreferencesService struct {
	contexts *vprocore.ContextService
	snapshot vprocore.PublicationReadSnapshotHooks
}

func NewSiteUnitSummaryPreferencesService(contexts *vprocore.ContextService) *SiteUnitSummaryPreferencesService {
	return &SiteUnitSummaryPreferencesService{contexts: contexts}
}

func (s *SiteUnitSummaryPreferencesService) helper() vprocore.ReportPreferenceHelper {
	if s == nil {
		return vprocore.ReportPreferenceHelper{}
	}
	return vprocore.ReportPreferenceHelper{Contexts: s.contexts, Snapshot: s.snapshot}
}

func (s *SiteUnitSummaryPreferencesService) GetSiteUnitSummaryPreferences(ctx context.Context, contextID string) (*SiteUnitSummaryOptions, error) {
	h := s.helper()
	if err := vprocore.RequireReportPreferenceContext(ctx, h, contextID, "Summary Environment"); err != nil {
		return nil, err
	}
	options, err := ReadSiteUnitSummaryOptions(s.contexts, ctx, contextID, s.snapshot)
	if err != nil {
		return nil, err
	}
	return &options, nil
}

func (s *SiteUnitSummaryPreferencesService) SaveSiteUnitSummaryPreferences(ctx context.Context,
	contextID, requestJSON string) *SiteUnitSummaryPreferencesOutcome {
	out := SiteUnitSummaryPreferencesOutcome(vprocore.SaveOwnedReportPreferences(ctx, s.helper(), contextID, requestJSON, "Summary Environment",
		func(owner *vprocore.SqliteContext, _ *sql.Tx, request SiteUnitSummaryPreferencesRequest) error {
			if request.Proposed.SiteUnitType == 1 && owner.Selection.SU == "None" {
				return errors.New("Summary Environment preferences require an explicitly selected normal SU")
			}
			return nil
		},
		func(plots *vprocore.PlotService, request SiteUnitSummaryPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
			return CompareAndSetSiteUnitSummaryPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
		}))
	return &out
}

type siteUnitSummaryIntFieldSpec struct {
	key  string
	min  int
	max  int
	name string
}

var siteUnitSummaryFullFieldSpecs = []siteUnitSummaryIntFieldSpec{
	{key: "SEOptValueMethod", min: 1, max: 2, name: "Method (1-2)"},
	{key: "SESuType", min: 1, max: 3, name: "SiteUnitType (1-3)"},
	{key: "SEIncludeSppSummary", min: 0, max: 1, name: "IncludeSpecies (0-1)"},
	{key: "SEOrderBy", min: 1, max: 3, name: "OrderBy (1-3)"},
	{key: "SECoverCalc", min: 1, max: 2, name: "CoverCalculation (1-2)"},
	{key: "SEOptAndOr", min: 1, max: 2, name: "AndOr (1-2)"},
	{key: "SESelectSppPresent", min: 0, max: 32767, name: "PresenceGreaterThan (0-32767)"},
	{key: "SESelectSppCover", min: 0, max: 32767, name: "CoverGreaterThan (0-32767)"},
}

// SiteUnitSummaryFullPreferenceValues captures all 8 ReportOptions.SE* preferences cleanly without legacy YAML leftovers.
type SiteUnitSummaryFullPreferenceValues struct {
	Method              int `json:"method"`
	SiteUnitType        int `json:"siteUnitType"`
	IncludeSpecies      int `json:"includeSpecies"`
	OrderBy             int `json:"orderBy"`
	CoverCalculation    int `json:"coverCalculation"`
	AndOr               int `json:"andOr"`
	PresenceGreaterThan int `json:"presenceGreaterThan"`
	CoverGreaterThan    int `json:"coverGreaterThan"`
}

func (values *SiteUnitSummaryFullPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain SiteUnitSummaryFullPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Summary Environment full preferences",
		"method", "siteUnitType", "includeSpecies", "orderBy",
		"coverCalculation", "andOr", "presenceGreaterThan", "coverGreaterThan"); err != nil {
		return err
	}
	*values = SiteUnitSummaryFullPreferenceValues(decoded)
	return nil
}

func (values SiteUnitSummaryFullPreferenceValues) ints() [8]int {
	return [8]int{
		values.Method, values.SiteUnitType, values.IncludeSpecies, values.OrderBy,
		values.CoverCalculation, values.AndOr, values.PresenceGreaterThan, values.CoverGreaterThan,
	}
}

func siteUnitSummaryFullValuesFromArray(raw [8]int) SiteUnitSummaryFullPreferenceValues {
	return SiteUnitSummaryFullPreferenceValues{
		Method:              raw[0],
		SiteUnitType:        raw[1],
		IncludeSpecies:      raw[2],
		OrderBy:             raw[3],
		CoverCalculation:    raw[4],
		AndOr:               raw[5],
		PresenceGreaterThan: raw[6],
		CoverGreaterThan:    raw[7],
	}
}

type SiteUnitSummaryFullPreferencesRequest struct {
	Expected SiteUnitSummaryFullPreferenceValues `json:"expected"`
	Proposed SiteUnitSummaryFullPreferenceValues `json:"proposed"`
}

func (request *SiteUnitSummaryFullPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain SiteUnitSummaryFullPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Summary Environment full preference save", "expected", "proposed"); err != nil {
		return err
	}
	*request = SiteUnitSummaryFullPreferencesRequest(decoded)
	return nil
}

type SiteUnitSummaryFullPreferences struct {
	ContextID   string                              `json:"contextId"`
	Project     string                              `json:"project"`
	ProjectPath string                              `json:"projectPath"`
	SU          string                              `json:"su"`
	SUPath      string                              `json:"suPath"`
	Values      SiteUnitSummaryFullPreferenceValues `json:"values"`
}

func readSiteUnitSummaryFullPreferenceValues(ctx context.Context, config *vprocore.DesktopConfig) (SiteUnitSummaryFullPreferenceValues, error) {
	if config == nil {
		return SiteUnitSummaryFullPreferenceValues{}, errors.New("Summary Environment option configuration is unavailable")
	}
	if err := sqlutil.AcquireMutexLease(ctx, &config.Mu); err != nil {
		return SiteUnitSummaryFullPreferenceValues{}, err
	}
	defer config.Mu.Unlock()
	values, err := config.ReadLocked()
	if err != nil {
		return SiteUnitSummaryFullPreferenceValues{}, err
	}
	var raw [8]int
	for i, spec := range siteUnitSummaryFullFieldSpecs {
		raw[i], err = vprocore.ConfigInt(values, "ReportOptions", spec.key, spec.min, spec.max)
		if err != nil {
			return SiteUnitSummaryFullPreferenceValues{}, err
		}
	}
	if err := ctx.Err(); err != nil {
		return SiteUnitSummaryFullPreferenceValues{}, err
	}
	return siteUnitSummaryFullValuesFromArray(raw), nil
}

func validateSiteUnitSummaryFullPreferenceValues(proposed SiteUnitSummaryFullPreferenceValues) error {
	vals := proposed.ints()
	for i, spec := range siteUnitSummaryFullFieldSpecs {
		if vals[i] < spec.min || vals[i] > spec.max {
			return errors.New("Summary Environment requires valid " + spec.name)
		}
	}
	return nil
}

func CompareAndSetSiteUnitSummaryFullPreferences(s *vprocore.DesktopConfig, ctx context.Context,
	expected, proposed SiteUnitSummaryFullPreferenceValues) (vprocore.ReportPreferenceUpdate, error) {
	if err := validateSiteUnitSummaryFullPreferenceValues(proposed); err != nil {
		return vprocore.ReportPreferenceUpdate{}, err
	}
	expVals := expected.ints()
	propVals := proposed.ints()
	changes := make([]vprocore.ReportPreferenceChange[int], len(siteUnitSummaryFullFieldSpecs))
	for i, spec := range siteUnitSummaryFullFieldSpecs {
		changes[i] = vprocore.ReportPreferenceChange[int]{Key: spec.key, Expected: expVals[i], Proposed: propVals[i]}
	}
	return vprocore.CompareAndSetReportPreferences(s, ctx, "Summary Environment full preferences", changes, func(values vprocore.ConfigValues, key string) (int, error) {
		for _, spec := range siteUnitSummaryFullFieldSpecs {
			if spec.key == key {
				return vprocore.ConfigInt(values, "ReportOptions", key, spec.min, spec.max)
			}
		}
		return 0, errors.New("unknown Summary Environment preference key: " + key)
	})
}

func (s *SiteUnitSummaryPreferencesService) GetFullSiteUnitSummaryPreferences(ctx context.Context, contextID string) (*SiteUnitSummaryFullPreferences, error) {
	h := s.helper()
	if err := vprocore.RequireReportPreferenceContext(ctx, h, contextID, "Summary Environment full"); err != nil {
		return nil, err
	}
	prefs, err := ReadSiteUnitSummaryFullPreferences(s.contexts, ctx, contextID, s.snapshot)
	if err != nil {
		return nil, err
	}
	return &prefs, nil
}

func (s *SiteUnitSummaryPreferencesService) SaveFullSiteUnitSummaryPreferences(ctx context.Context,
	contextID, requestJSON string) *SiteUnitSummaryPreferencesOutcome {
	out := SiteUnitSummaryPreferencesOutcome(vprocore.SaveOwnedReportPreferences(ctx, s.helper(), contextID, requestJSON, "Summary Environment full",
		func(owner *vprocore.SqliteContext, _ *sql.Tx, request SiteUnitSummaryFullPreferencesRequest) error {
			if request.Proposed.SiteUnitType == 1 && owner.Selection.SU == "None" {
				return errors.New("Summary Environment preferences require an explicitly selected normal SU")
			}
			if request.Proposed.SiteUnitType == 2 && (owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None") {
				return errors.New("Summary Environment hierarchy breakpoints require an active hierarchy")
			}
			return nil
		},
		func(plots *vprocore.PlotService, request SiteUnitSummaryFullPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
			return CompareAndSetSiteUnitSummaryFullPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
		}))
	return &out
}
