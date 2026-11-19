package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"reflect"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// 6. Long Vegetation Quality Include Nulls Preferences

type LongVegetationQualityNullPreferenceValues struct {
	SiteIncludeNulls bool `json:"siteIncludeNulls"`
	VegIncludeNulls  bool `json:"vegIncludeNulls"`
	SoilIncludeNulls bool `json:"soilIncludeNulls"`
}

func (v *LongVegetationQualityNullPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationQualityNullPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation quality Include Nulls preferences",
		"siteIncludeNulls", "vegIncludeNulls", "soilIncludeNulls"); err != nil {
		return err
	}
	*v = LongVegetationQualityNullPreferenceValues(decoded)
	return nil
}

type LongVegetationQualityNullPreferencesRequest struct {
	Expected LongVegetationQualityNullPreferenceValues `json:"expected"`
	Proposed LongVegetationQualityNullPreferenceValues `json:"proposed"`
}

func (v *LongVegetationQualityNullPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationQualityNullPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation quality Include Nulls preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationQualityNullPreferencesRequest(decoded)
	return nil
}

type LongVegetationQualityNullPreferencesReview struct {
	ContextID   string                                    `json:"contextId"`
	Project     string                                    `json:"project"`
	ProjectPath string                                    `json:"projectPath"`
	SU          string                                    `json:"su"`
	SUPath      string                                    `json:"suPath"`
	Values      LongVegetationQualityNullPreferenceValues `json:"values"`
}

type LongVegetationQualityNullPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationQualityNullPreferencesService struct {
	reportcore.PreferencesService[LongVegetationQualityNullPreferencesRequest, LongVegetationQualityNullPreferencesReview]
}

func NewLongVegetationQualityNullPreferencesService(contexts *vprocore.ContextService) *LongVegetationQualityNullPreferencesService {
	return &LongVegetationQualityNullPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationQualityNullPreferencesRequest, LongVegetationQualityNullPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation quality Include Nulls",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationQualityNullPreferencesReview, error) {
				values, err := ReadLongVegetationQualityNullPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationQualityNullPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: values,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationQualityNullPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				return CompareAndSetLongVegetationQualityNullPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationQualityNullPreferencesService) GetLongVegetationQualityNullPreferences(ctx context.Context, contextID string) (*LongVegetationQualityNullPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation quality Include Nulls preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationQualityNullPreferencesService) SaveLongVegetationQualityNullPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationQualityNullPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation quality Include Nulls preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}

// 7. Long Vegetation Quality Minimum Preferences

const longVegetationQualityMinimumSuggestionsSource = "configured-owned-imported-SQLite VLists.USysTableOfLists; PlotQualitySite; ItemOrder then physical rowid; suggestions only"

type LongVegetationQualityMinimumPreferenceValues struct {
	SiteMinimum string `json:"siteMinimum"`
	VegMinimum  string `json:"vegMinimum"`
	SoilMinimum string `json:"soilMinimum"`
}

func (v *LongVegetationQualityMinimumPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationQualityMinimumPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation quality minimum preferences",
		"siteMinimum", "vegMinimum", "soilMinimum"); err != nil {
		return err
	}
	*v = LongVegetationQualityMinimumPreferenceValues(decoded)
	return nil
}

type LongVegetationQualityMinimumPreferencesRequest struct {
	Expected LongVegetationQualityMinimumPreferenceValues `json:"expected"`
	Proposed LongVegetationQualityMinimumPreferenceValues `json:"proposed"`
}

func (v *LongVegetationQualityMinimumPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationQualityMinimumPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation quality minimum preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationQualityMinimumPreferencesRequest(decoded)
	return nil
}

type LongVegetationQualityMinimumPreferencesReview struct {
	ContextID   string                                       `json:"contextId"`
	Project     string                                       `json:"project"`
	ProjectPath string                                       `json:"projectPath"`
	SU          string                                       `json:"su"`
	SUPath      string                                       `json:"suPath"`
	Values      LongVegetationQualityMinimumPreferenceValues `json:"values"`
	Source      string                                       `json:"source"`
	Definitions vprocore.ProjectMetadataTable                `json:"definitions"`
}

type LongVegetationQualityMinimumPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationQualityMinimumPreferencesService struct {
	reportcore.PreferencesService[LongVegetationQualityMinimumPreferencesRequest, LongVegetationQualityMinimumPreferencesReview]
}

func readLongVegetationQualityMinimumSuggestions(ctx context.Context, tx *sql.Tx) (vprocore.ProjectMetadataTable, error) {
	if err := vprocore.ValidateSIVIPhysicalSchema(ctx, tx, "VLists", "USysTableOfLists", "Long Vegetation quality minimum suggestions"); err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	table, err := vprocore.ReadSQLiteLiteralTextRows(ctx, tx, "VLists", "USysTableOfLists", "ListName", "PlotQualitySite", "ItemOrder")
	if err != nil {
		return vprocore.ProjectMetadataTable{}, err
	}
	if !reflect.DeepEqual(table.Columns, sourceform.SourceParentReferenceColumns) {
		return vprocore.ProjectMetadataTable{}, errors.New("Long Vegetation quality minimum suggestions require the exact ten-column imported schema")
	}
	return table, nil
}

func NewLongVegetationQualityMinimumPreferencesService(contexts *vprocore.ContextService) *LongVegetationQualityMinimumPreferencesService {
	return &LongVegetationQualityMinimumPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationQualityMinimumPreferencesRequest, LongVegetationQualityMinimumPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation quality minimum",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, tx *sql.Tx) (*LongVegetationQualityMinimumPreferencesReview, error) {
				definitions, err := readLongVegetationQualityMinimumSuggestions(ctx, tx)
				if err != nil {
					return nil, err
				}
				values, err := ReadLongVegetationQualityMinimumPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationQualityMinimumPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath,
					Values: values, Source: longVegetationQualityMinimumSuggestionsSource, Definitions: definitions,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationQualityMinimumPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				return CompareAndSetLongVegetationQualityMinimumPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationQualityMinimumPreferencesService) GetLongVegetationQualityMinimumPreferences(ctx context.Context, contextID string) (*LongVegetationQualityMinimumPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation quality minimum preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationQualityMinimumPreferencesService) SaveLongVegetationQualityMinimumPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationQualityMinimumPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation quality minimum preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}

// 8. Long Vegetation Naming (Show) Preferences

type LongVegetationNamingPreferenceValues struct {
	Mode          int    `json:"mode"`
	SelectedField string `json:"selectedField"`
}

func (v *LongVegetationNamingPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationNamingPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation Show preferences", "mode", "selectedField"); err != nil {
		return err
	}
	if !longVegetationNamingMode(decoded.Mode) {
		return errors.New("Long Vegetation Show requires source mode 0, 1, 2 or historical selected-field mode 4")
	}
	*v = LongVegetationNamingPreferenceValues(decoded)
	return nil
}

type LongVegetationNamingPreferencesRequest struct {
	Expected LongVegetationNamingPreferenceValues `json:"expected"`
	Proposed LongVegetationNamingPreferenceValues `json:"proposed"`
}

func (v *LongVegetationNamingPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationNamingPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation Show preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationNamingPreferencesRequest(decoded)
	return nil
}

type LongVegetationNamingAvailability struct {
	None          bool `json:"none"`
	English       bool `json:"english"`
	Code          bool `json:"code"`
	SelectedField bool `json:"selectedField"`
}

func (a LongVegetationNamingAvailability) allows(mode int) bool {
	switch mode {
	case 0:
		return a.None
	case 1:
		return a.English
	case 2:
		return a.Code
	default:
		return false
	}
}

type LongVegetationNamingPreferencesReview struct {
	ContextID    string                               `json:"contextId"`
	Project      string                               `json:"project"`
	ProjectPath  string                               `json:"projectPath"`
	SU           string                               `json:"su"`
	SUPath       string                               `json:"suPath"`
	Values       LongVegetationNamingPreferenceValues `json:"values"`
	Availability LongVegetationNamingAvailability     `json:"availability"`
}

type LongVegetationNamingPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationNamingPreferencesService struct {
	reportcore.PreferencesService[LongVegetationNamingPreferencesRequest, LongVegetationNamingPreferencesReview]
}

func NewLongVegetationNamingPreferencesService(contexts *vprocore.ContextService) *LongVegetationNamingPreferencesService {
	avail := LongVegetationNamingAvailability{None: true, English: true, Code: true}
	return &LongVegetationNamingPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationNamingPreferencesRequest, LongVegetationNamingPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation Show",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationNamingPreferencesReview, error) {
				values, err := ReadLongVegetationNamingPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationNamingPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: values, Availability: avail,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationNamingPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				if request.Expected != request.Proposed && !avail.allows(request.Proposed.Mode) {
					return vprocore.ReportPreferenceUpdate{}, fmt.Errorf("Long Vegetation Show choice %d is unavailable on this control; saved naming values were not reset", request.Proposed.Mode)
				}
				return CompareAndSetLongVegetationNamingPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationNamingPreferencesService) GetLongVegetationNamingPreferences(ctx context.Context, contextID string) (*LongVegetationNamingPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation Show preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationNamingPreferencesService) SaveLongVegetationNamingPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationNamingPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation Show preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}
