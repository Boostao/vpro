package vegreport

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// 1. Long Vegetation Report Title Preferences

type LongVegetationPreferenceValues struct {
	Title string `json:"title"`
}

func (v *LongVegetationPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation preferences", "title"); err != nil {
		return err
	}
	*v = LongVegetationPreferenceValues(decoded)
	return nil
}

type LongVegetationPreferencesRequest struct {
	Expected LongVegetationPreferenceValues `json:"expected"`
	Proposed LongVegetationPreferenceValues `json:"proposed"`
}

func (v *LongVegetationPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationPreferencesRequest(decoded)
	return nil
}

type LongVegetationPreferencesReview struct {
	ContextID   string                         `json:"contextId"`
	Project     string                         `json:"project"`
	ProjectPath string                         `json:"projectPath"`
	SU          string                         `json:"su"`
	SUPath      string                         `json:"suPath"`
	Values      LongVegetationPreferenceValues `json:"values"`
}

type LongVegetationPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationPreferencesService struct {
	reportcore.PreferencesService[LongVegetationPreferencesRequest, LongVegetationPreferencesReview]
}

func NewLongVegetationPreferencesService(contexts *vprocore.ContextService) *LongVegetationPreferencesService {
	return &LongVegetationPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationPreferencesRequest, LongVegetationPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationPreferencesReview, error) {
				title, err := ReadLongVegetationPreference(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				if err := vprocore.ValidateGoogleEarthReviewStrings(title); err != nil {
					return nil, err
				}
				return &LongVegetationPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: LongVegetationPreferenceValues{Title: title},
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				return CompareAndSetLongVegetationPreference(plots.Projects.Preferences, ctx, request.Expected.Title, request.Proposed.Title)
			},
		},
	}
}

func (s *LongVegetationPreferencesService) GetLongVegetationPreferences(ctx context.Context, contextID string) (*LongVegetationPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationPreferencesService) SaveLongVegetationPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}

// 2. Long Vegetation Statistics Preferences

type LongVegetationStatisticsPreferenceValues struct {
	AvgType int `json:"avgType"`
	OrderBy int `json:"orderBy"`
}

func (v *LongVegetationStatisticsPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationStatisticsPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation statistics preferences", "avgType", "orderBy"); err != nil {
		return err
	}
	*v = LongVegetationStatisticsPreferenceValues(decoded)
	return nil
}

type LongVegetationStatisticsPreferencesRequest struct {
	Expected LongVegetationStatisticsPreferenceValues `json:"expected"`
	Proposed LongVegetationStatisticsPreferenceValues `json:"proposed"`
}

func (v *LongVegetationStatisticsPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationStatisticsPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation statistics preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationStatisticsPreferencesRequest(decoded)
	return nil
}

type LongVegetationStatisticsPreferencesReview struct {
	ContextID   string                                   `json:"contextId"`
	Project     string                                   `json:"project"`
	ProjectPath string                                   `json:"projectPath"`
	SU          string                                   `json:"su"`
	SUPath      string                                   `json:"suPath"`
	Values      LongVegetationStatisticsPreferenceValues `json:"values"`
}

type LongVegetationStatisticsPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationStatisticsPreferencesService struct {
	reportcore.PreferencesService[LongVegetationStatisticsPreferencesRequest, LongVegetationStatisticsPreferencesReview]
}

func NewLongVegetationStatisticsPreferencesService(contexts *vprocore.ContextService) *LongVegetationStatisticsPreferencesService {
	return &LongVegetationStatisticsPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationStatisticsPreferencesRequest, LongVegetationStatisticsPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation statistics",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationStatisticsPreferencesReview, error) {
				values, err := ReadLongVegetationStatisticsPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationStatisticsPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: values,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationStatisticsPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				return CompareAndSetLongVegetationStatisticsPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationStatisticsPreferencesService) GetLongVegetationStatisticsPreferences(ctx context.Context, contextID string) (*LongVegetationStatisticsPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation statistics preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationStatisticsPreferencesService) SaveLongVegetationStatisticsPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationStatisticsPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation statistics preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}

// 3. Long Vegetation Switch Preferences

type LongVegetationSwitchPreferenceValues struct {
	QuickReport         bool `json:"quickReport"`
	SpaceBetweenGroups  bool `json:"spaceBetweenGroups"`
	ReportSummary       bool `json:"reportSummary"`
	ConstantSpeciesList bool `json:"constantSpeciesList"`
}

func (v *LongVegetationSwitchPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationSwitchPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation switch preferences",
		"quickReport", "spaceBetweenGroups", "reportSummary", "constantSpeciesList"); err != nil {
		return err
	}
	*v = LongVegetationSwitchPreferenceValues(decoded)
	return nil
}

type LongVegetationSwitchPreferencesRequest struct {
	Expected LongVegetationSwitchPreferenceValues `json:"expected"`
	Proposed LongVegetationSwitchPreferenceValues `json:"proposed"`
}

func (v *LongVegetationSwitchPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationSwitchPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation switch preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationSwitchPreferencesRequest(decoded)
	return nil
}

type LongVegetationSwitchPreferencesReview struct {
	ContextID   string                               `json:"contextId"`
	Project     string                               `json:"project"`
	ProjectPath string                               `json:"projectPath"`
	SU          string                               `json:"su"`
	SUPath      string                               `json:"suPath"`
	Values      LongVegetationSwitchPreferenceValues `json:"values"`
}

type LongVegetationSwitchPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationSwitchPreferencesService struct {
	reportcore.PreferencesService[LongVegetationSwitchPreferencesRequest, LongVegetationSwitchPreferencesReview]
}

func NewLongVegetationSwitchPreferencesService(contexts *vprocore.ContextService) *LongVegetationSwitchPreferencesService {
	return &LongVegetationSwitchPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationSwitchPreferencesRequest, LongVegetationSwitchPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation switch",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationSwitchPreferencesReview, error) {
				values, err := ReadLongVegetationSwitchPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationSwitchPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: values,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationSwitchPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				return CompareAndSetLongVegetationSwitchPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationSwitchPreferencesService) GetLongVegetationSwitchPreferences(ctx context.Context, contextID string) (*LongVegetationSwitchPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation switch preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationSwitchPreferencesService) SaveLongVegetationSwitchPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationSwitchPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation switch preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}

// 4. Long Vegetation Threshold Preferences

type LongVegetationThresholdPreferenceValues struct {
	PresenceGreaterThan  float64 `json:"presenceGreaterThan"`
	MeanCoverGreaterThan float64 `json:"meanCoverGreaterThan"`
}

func (v *LongVegetationThresholdPreferenceValues) UnmarshalJSON(data []byte) error {
	var decoded struct {
		PresenceGreaterThan  json.RawMessage `json:"presenceGreaterThan"`
		MeanCoverGreaterThan json.RawMessage `json:"meanCoverGreaterThan"`
	}
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation threshold preferences",
		"presenceGreaterThan", "meanCoverGreaterThan"); err != nil {
		return err
	}
	presence, err := decodeLongVegetationThresholdNumber(decoded.PresenceGreaterThan, "presence")
	if err != nil {
		return err
	}
	cover, err := decodeLongVegetationThresholdNumber(decoded.MeanCoverGreaterThan, "mean cover")
	if err != nil {
		return err
	}
	*v = LongVegetationThresholdPreferenceValues{PresenceGreaterThan: presence, MeanCoverGreaterThan: cover}
	return nil
}

func decodeLongVegetationThresholdNumber(data []byte, field string) (float64, error) {
	var decoded *float64
	if err := json.Unmarshal(data, &decoded); err != nil {
		return 0, fmt.Errorf("Long Vegetation %s threshold requires a finite JSON number: %w", field, err)
	}
	if decoded == nil {
		return 0, fmt.Errorf("Long Vegetation %s threshold requires a finite JSON number, not NULL", field)
	}
	value := *decoded
	mantissa := strings.FieldsFunc(string(data), func(r rune) bool { return r == 'e' || r == 'E' })[0]
	if value == 0 && strings.ContainsAny(mantissa, "123456789") {
		return 0, fmt.Errorf("Long Vegetation %s threshold underflows the finite DOUBLE domain", field)
	}
	return value, nil
}

type LongVegetationThresholdPreferencesRequest struct {
	Expected LongVegetationThresholdPreferenceValues `json:"expected"`
	Proposed LongVegetationThresholdPreferenceValues `json:"proposed"`
}

func (v *LongVegetationThresholdPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationThresholdPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation threshold preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationThresholdPreferencesRequest(decoded)
	return nil
}

type LongVegetationThresholdPreferencesReview struct {
	ContextID   string                                  `json:"contextId"`
	Project     string                                  `json:"project"`
	ProjectPath string                                  `json:"projectPath"`
	SU          string                                  `json:"su"`
	SUPath      string                                  `json:"suPath"`
	Values      LongVegetationThresholdPreferenceValues `json:"values"`
}

type LongVegetationThresholdPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationThresholdPreferencesService struct {
	reportcore.PreferencesService[LongVegetationThresholdPreferencesRequest, LongVegetationThresholdPreferencesReview]
}

func NewLongVegetationThresholdPreferencesService(contexts *vprocore.ContextService) *LongVegetationThresholdPreferencesService {
	return &LongVegetationThresholdPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationThresholdPreferencesRequest, LongVegetationThresholdPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation threshold",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationThresholdPreferencesReview, error) {
				values, err := ReadLongVegetationThresholdPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationThresholdPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: values,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationThresholdPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				return CompareAndSetLongVegetationThresholdPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationThresholdPreferencesService) GetLongVegetationThresholdPreferences(ctx context.Context, contextID string) (*LongVegetationThresholdPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation threshold preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationThresholdPreferencesService) SaveLongVegetationThresholdPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationThresholdPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation threshold preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}

// 5. Long Vegetation Grouping Preferences

type LongVegetationGroupPreferenceValues struct {
	GroupBy int `json:"groupBy"`
}

func (v *LongVegetationGroupPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationGroupPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation grouping preferences", "groupBy"); err != nil {
		return err
	}
	if decoded.GroupBy < 1 || decoded.GroupBy > 4 {
		return errors.New("Long Vegetation Group by requires source choice 1, 2, 3 or 4")
	}
	*v = LongVegetationGroupPreferenceValues(decoded)
	return nil
}

type LongVegetationGroupPreferencesRequest struct {
	Expected LongVegetationGroupPreferenceValues `json:"expected"`
	Proposed LongVegetationGroupPreferenceValues `json:"proposed"`
}

func (v *LongVegetationGroupPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationGroupPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation grouping preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationGroupPreferencesRequest(decoded)
	return nil
}

type LongVegetationGroupAvailability struct {
	Layer    bool `json:"layer"`
	Strata   bool `json:"strata"`
	Lifeform bool `json:"lifeform"`
	None     bool `json:"none"`
}

func (a LongVegetationGroupAvailability) allows(group int) bool {
	switch group {
	case 1:
		return a.Layer
	case 2:
		return a.Strata
	case 3:
		return a.Lifeform
	case 4:
		return a.None
	default:
		return false
	}
}

type LongVegetationGroupPreferencesReview struct {
	ContextID    string                              `json:"contextId"`
	Project      string                              `json:"project"`
	ProjectPath  string                              `json:"projectPath"`
	SU           string                              `json:"su"`
	SUPath       string                              `json:"suPath"`
	Values       LongVegetationGroupPreferenceValues `json:"values"`
	Availability LongVegetationGroupAvailability     `json:"availability"`
}

type LongVegetationGroupPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationGroupPreferencesService struct {
	reportcore.PreferencesService[LongVegetationGroupPreferencesRequest, LongVegetationGroupPreferencesReview]
}

func NewLongVegetationGroupPreferencesService(contexts *vprocore.ContextService) *LongVegetationGroupPreferencesService {
	avail := LongVegetationGroupAvailability{Layer: true, Strata: true, Lifeform: true, None: true}
	return &LongVegetationGroupPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationGroupPreferencesRequest, LongVegetationGroupPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation grouping",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationGroupPreferencesReview, error) {
				values, err := ReadLongVegetationGroupPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationGroupPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: values, Availability: avail,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationGroupPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				if request.Expected.GroupBy != request.Proposed.GroupBy && !avail.allows(request.Proposed.GroupBy) {
					return vprocore.ReportPreferenceUpdate{}, fmt.Errorf("Long Vegetation grouping choice %d is unavailable; saved LVGroupBy was not reset", request.Proposed.GroupBy)
				}
				return CompareAndSetLongVegetationGroupPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationGroupPreferencesService) GetLongVegetationGroupPreferences(ctx context.Context, contextID string) (*LongVegetationGroupPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation grouping preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationGroupPreferencesService) SaveLongVegetationGroupPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationGroupPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation grouping preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}
