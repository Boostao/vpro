package vegreport

import (
	"context"
	"encoding/json"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// LongVegetationAllPreferencesService consolidates all 11 per-tab Long Vegetation
// preference sub-services into one cohesive domain service (ENG-GO-009).
type LongVegetationAllPreferencesService struct {
	Title         *LongVegetationPreferencesService
	Statistics    *LongVegetationStatisticsPreferencesService
	Switch        *LongVegetationSwitchPreferencesService
	Threshold     *LongVegetationThresholdPreferencesService
	Group         *LongVegetationGroupPreferencesService
	QualityNull   *LongVegetationQualityNullPreferencesService
	QualityMin    *LongVegetationQualityMinimumPreferencesService
	Naming        *LongVegetationNamingPreferencesService
	SelectedField *LongVegetationSelectedFieldPreferencesService
	Enforcement   *LongVegetationEnforcementPreferencesService
	Unit          *LongVegetationUnitPreferencesService
}

func NewLongVegetationAllPreferencesService(contexts *vprocore.ContextService) *LongVegetationAllPreferencesService {
	return &LongVegetationAllPreferencesService{
		Title:         NewLongVegetationPreferencesService(contexts),
		Statistics:    NewLongVegetationStatisticsPreferencesService(contexts),
		Switch:        NewLongVegetationSwitchPreferencesService(contexts),
		Threshold:     NewLongVegetationThresholdPreferencesService(contexts),
		Group:         NewLongVegetationGroupPreferencesService(contexts),
		QualityNull:   NewLongVegetationQualityNullPreferencesService(contexts),
		QualityMin:    NewLongVegetationQualityMinimumPreferencesService(contexts),
		Naming:        NewLongVegetationNamingPreferencesService(contexts),
		SelectedField: NewLongVegetationSelectedFieldPreferencesService(contexts),
		Enforcement:   NewLongVegetationEnforcementPreferencesService(contexts),
		Unit:          NewLongVegetationUnitPreferencesService(contexts),
	}
}

// LongVegetationTabPreferencesBundle returns the complete typed Long Vegetation
// YAML preference state across tabs in one call.
type LongVegetationTabPreferencesBundle struct {
	Title         *LongVegetationPreferencesReview               `json:"title"`
	Statistics    *LongVegetationStatisticsPreferencesReview     `json:"statistics"`
	Switch        *LongVegetationSwitchPreferencesReview         `json:"switch"`
	Threshold     *LongVegetationThresholdPreferencesReview      `json:"threshold"`
	Group         *LongVegetationGroupPreferencesReview          `json:"group"`
	QualityNull   *LongVegetationQualityNullPreferencesReview    `json:"qualityNull"`
	QualityMin    *LongVegetationQualityMinimumPreferencesReview `json:"qualityMinimum"`
	Naming        *LongVegetationNamingPreferencesReview         `json:"naming"`
	SelectedField *LongVegetationSelectedFieldPreferencesReview  `json:"selectedField,omitempty"`
	Enforcement   *LongVegetationEnforcementPreferencesReview    `json:"enforcement"`
	Unit          *LongVegetationUnitPreferencesReview           `json:"unit,omitempty"`
	TabErrors     map[string]string                              `json:"tabErrors,omitempty"`
}

func (s *LongVegetationAllPreferencesService) GetAll(ctx context.Context, contextID string) (*LongVegetationTabPreferencesBundle, error) {
	title, err := s.Title.GetLongVegetationPreferences(ctx, contextID)
	if err != nil {
		return nil, err
	}
	bundle := &LongVegetationTabPreferencesBundle{Title: title}
	recordErr := func(tab string, e error) {
		if e == nil {
			return
		}
		if bundle.TabErrors == nil {
			bundle.TabErrors = make(map[string]string)
		}
		bundle.TabErrors[tab] = e.Error()
	}
	var tabErr error
	bundle.Statistics, tabErr = s.Statistics.GetLongVegetationStatisticsPreferences(ctx, contextID)
	recordErr("statistics", tabErr)
	bundle.Switch, tabErr = s.Switch.GetLongVegetationSwitchPreferences(ctx, contextID)
	recordErr("switch", tabErr)
	bundle.Threshold, tabErr = s.Threshold.GetLongVegetationThresholdPreferences(ctx, contextID)
	recordErr("threshold", tabErr)
	bundle.Group, tabErr = s.Group.GetLongVegetationGroupPreferences(ctx, contextID)
	recordErr("group", tabErr)
	bundle.QualityNull, tabErr = s.QualityNull.GetLongVegetationQualityNullPreferences(ctx, contextID)
	recordErr("qualityNull", tabErr)
	bundle.QualityMin, tabErr = s.QualityMin.GetLongVegetationQualityMinimumPreferences(ctx, contextID)
	recordErr("qualityMinimum", tabErr)
	bundle.Naming, tabErr = s.Naming.GetLongVegetationNamingPreferences(ctx, contextID)
	recordErr("naming", tabErr)
	bundle.SelectedField, tabErr = s.SelectedField.GetLongVegetationSelectedFieldPreferences(ctx, contextID)
	recordErr("selectedField", tabErr)
	bundle.Enforcement, tabErr = s.Enforcement.GetLongVegetationEnforcementPreferences(ctx, contextID)
	recordErr("enforcement", tabErr)
	bundle.Unit, tabErr = s.Unit.GetLongVegetationUnitPreferences(ctx, contextID)
	recordErr("unit", tabErr)
	return bundle, nil
}

// LongVegetationTabPreferencesSaveRequest saves any single Long Vegetation preference tab
// via one typed Wails RPC contract (ENG-GO-009).
type LongVegetationTabPreferencesSaveRequest struct {
	Tab            string                                          `json:"tab"`
	Title          *LongVegetationPreferencesRequest               `json:"title,omitempty"`
	Statistics     *LongVegetationStatisticsPreferencesRequest     `json:"statistics,omitempty"`
	Switch         *LongVegetationSwitchPreferencesRequest         `json:"switch,omitempty"`
	Threshold      *LongVegetationThresholdPreferencesRequest      `json:"threshold,omitempty"`
	Group          *LongVegetationGroupPreferencesRequest          `json:"group,omitempty"`
	QualityNull    *LongVegetationQualityNullPreferencesRequest    `json:"qualityNull,omitempty"`
	QualityMinimum *LongVegetationQualityMinimumPreferencesRequest `json:"qualityMinimum,omitempty"`
	Naming         *LongVegetationNamingPreferencesRequest         `json:"naming,omitempty"`
	SelectedField  *LongVegetationSelectedFieldPreferencesRequest  `json:"selectedField,omitempty"`
	Enforcement    *LongVegetationEnforcementPreferencesRequest    `json:"enforcement,omitempty"`
	Unit           *LongVegetationUnitPreferencesRequest           `json:"unit,omitempty"`
}

func saveTypedTab[Req any](ctx context.Context, contextID string, payload *Req, tab string, fn func(context.Context, string, string) *vprocore.ReportPreferenceOutcome) *vprocore.ReportPreferenceOutcome {
	if payload == nil {
		return &vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation " + tab + " preference payload is required"}
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return &vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: err.Error()}
	}
	return fn(ctx, contextID, string(raw))
}

func (s *LongVegetationAllPreferencesService) SaveTab(ctx context.Context, contextID string, req LongVegetationTabPreferencesSaveRequest) *vprocore.ReportPreferenceOutcome {
	if s == nil {
		return &vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "long vegetation preferences service is unavailable"}
	}
	switch req.Tab {
	case "title":
		return saveTypedTab(ctx, contextID, req.Title, "title", s.Title.SaveLongVegetationPreferences)
	case "statistics":
		return saveTypedTab(ctx, contextID, req.Statistics, "statistics", s.Statistics.SaveLongVegetationStatisticsPreferences)
	case "switch":
		return saveTypedTab(ctx, contextID, req.Switch, "switch", s.Switch.SaveLongVegetationSwitchPreferences)
	case "threshold":
		return saveTypedTab(ctx, contextID, req.Threshold, "threshold", s.Threshold.SaveLongVegetationThresholdPreferences)
	case "group":
		return saveTypedTab(ctx, contextID, req.Group, "group", s.Group.SaveLongVegetationGroupPreferences)
	case "qualityNull":
		return saveTypedTab(ctx, contextID, req.QualityNull, "quality null", s.QualityNull.SaveLongVegetationQualityNullPreferences)
	case "qualityMinimum":
		return saveTypedTab(ctx, contextID, req.QualityMinimum, "quality minimum", s.QualityMin.SaveLongVegetationQualityMinimumPreferences)
	case "naming":
		return saveTypedTab(ctx, contextID, req.Naming, "naming", s.Naming.SaveLongVegetationNamingPreferences)
	case "selectedField":
		return saveTypedTab(ctx, contextID, req.SelectedField, "selected field", s.SelectedField.SaveLongVegetationSelectedFieldPreferences)
	case "enforcement":
		return saveTypedTab(ctx, contextID, req.Enforcement, "enforcement", func(ctx context.Context, cid, raw string) *vprocore.ReportPreferenceOutcome {
			out := s.Enforcement.SaveLongVegetationEnforcementPreferences(ctx, cid, raw)
			if out == nil {
				return &vprocore.ReportPreferenceOutcome{ContextID: cid, ErrorMessage: "long vegetation enforcement preferences service is unavailable"}
			}
			return &vprocore.ReportPreferenceOutcome{ContextID: out.ContextID, Changed: out.Changed, Committed: out.Committed, ErrorMessage: out.ErrorMessage}
		})
	case "unit":
		return saveTypedTab(ctx, contextID, req.Unit, "unit", func(ctx context.Context, cid, raw string) *vprocore.ReportPreferenceOutcome {
			out := s.Unit.SaveLongVegetationUnitPreferences(ctx, cid, raw)
			if out == nil {
				return &vprocore.ReportPreferenceOutcome{ContextID: cid, ErrorMessage: "long vegetation unit preferences service is unavailable"}
			}
			return &vprocore.ReportPreferenceOutcome{ContextID: out.ContextID, Changed: out.Changed, Committed: out.Committed, ErrorMessage: out.ErrorMessage}
		})
	default:
		return &vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "unsupported Long Vegetation preference tab"}
	}
}
