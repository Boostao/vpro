package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"reflect"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// 9. Long Vegetation Selected Field Preferences

const longVegetationSelectedFieldDefinitionsSource = "configured-owned-imported-SQLite VLists.USysAllSpecs physical columns; source Value List suggestions are not mandatory membership"

type LongVegetationSelectedFieldPreferenceValues struct {
	Mode          int    `json:"mode"`
	SelectedField string `json:"selectedField"`
}

func (v *LongVegetationSelectedFieldPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationSelectedFieldPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation selected field preferences", "mode", "selectedField"); err != nil {
		return err
	}
	if !longVegetationNamingMode(decoded.Mode) {
		return errors.New("Long Vegetation selected field requires source mode 0, 1, 2 or 4")
	}
	*v = LongVegetationSelectedFieldPreferenceValues(decoded)
	return nil
}

type LongVegetationSelectedFieldPreferencesRequest struct {
	Expected LongVegetationSelectedFieldPreferenceValues `json:"expected"`
	Proposed LongVegetationSelectedFieldPreferenceValues `json:"proposed"`
}

func (v *LongVegetationSelectedFieldPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationSelectedFieldPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation selected field preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationSelectedFieldPreferencesRequest(decoded)
	return nil
}

type LongVegetationSelectedFieldPreferencesReview struct {
	ContextID   string                                      `json:"contextId"`
	Project     string                                      `json:"project"`
	ProjectPath string                                      `json:"projectPath"`
	SU          string                                      `json:"su"`
	SUPath      string                                      `json:"suPath"`
	Values      LongVegetationSelectedFieldPreferenceValues `json:"values"`
	Source      string                                      `json:"source"`
	Definitions []vprocore.ProjectMetadataColumn            `json:"definitions"`
}

type LongVegetationSelectedFieldPreferencesOutcome = vprocore.ReportPreferenceOutcome

type LongVegetationSelectedFieldPreferencesService struct {
	reportcore.PreferencesService[LongVegetationSelectedFieldPreferencesRequest, LongVegetationSelectedFieldPreferencesReview]
}

func readLongVegetationSelectedFieldDefinitions(ctx context.Context, tx *sql.Tx) ([]vprocore.ProjectMetadataColumn, error) {
	var count int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM "VLists".sqlite_master WHERE type='table' AND name COLLATE BINARY=?`,
		"USysAllSpecs").Scan(&count); err != nil {
		return nil, err
	}
	if count != 1 {
		return nil, errors.New("Long Vegetation selected field definitions require original physical VLists.USysAllSpecs")
	}
	if err := vprocore.ValidateSIVIPhysicalSchema(ctx, tx, "VLists", "USysAllSpecs", "Long Vegetation selected field definitions"); err != nil {
		return nil, fmt.Errorf("Long Vegetation selected field definitions unavailable: %w", err)
	}
	return vprocore.ReadSQLiteStorageColumns(ctx, tx, "VLists", "USysAllSpecs")
}

func NewLongVegetationSelectedFieldPreferencesService(contexts *vprocore.ContextService) *LongVegetationSelectedFieldPreferencesService {
	return &LongVegetationSelectedFieldPreferencesService{
		PreferencesService: reportcore.PreferencesService[LongVegetationSelectedFieldPreferencesRequest, LongVegetationSelectedFieldPreferencesReview]{
			Contexts: contexts,
			Label:    "Long Vegetation selected field",
			ReadFn: func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, tx *sql.Tx) (*LongVegetationSelectedFieldPreferencesReview, error) {
				definitions, err := readLongVegetationSelectedFieldDefinitions(ctx, tx)
				if err != nil {
					return nil, err
				}
				values, err := ReadLongVegetationSelectedFieldPreferences(plots.Projects.Preferences, ctx)
				if err != nil {
					return nil, err
				}
				return &LongVegetationSelectedFieldPreferencesReview{
					ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
					SU: owner.Selection.SU, SUPath: owner.Selection.SUPath,
					Values: values, Source: longVegetationSelectedFieldDefinitionsSource, Definitions: definitions,
				}, nil
			},
			WriteFn: func(ctx context.Context, _ string, plots *vprocore.PlotService, request LongVegetationSelectedFieldPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
				return CompareAndSetLongVegetationSelectedFieldPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			},
		},
	}
}

func (s *LongVegetationSelectedFieldPreferencesService) GetLongVegetationSelectedFieldPreferences(ctx context.Context, contextID string) (*LongVegetationSelectedFieldPreferencesReview, error) {
	if s == nil {
		return nil, errors.New("Long Vegetation selected field preferences are unavailable")
	}
	return s.Get(ctx, contextID)
}

func (s *LongVegetationSelectedFieldPreferencesService) SaveLongVegetationSelectedFieldPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationSelectedFieldPreferencesOutcome {
	if s == nil {
		out := vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "Long Vegetation selected field preferences are unavailable"}
		return &out
	}
	out := s.SaveJSON(ctx, contextID, requestJSON)
	return &out
}

// 10. Long Vegetation Enforcement Preferences

type LongVegetationEnforcementPreferenceValues struct {
	Enforce    bool `json:"enforce"`
	UnitGroups int  `json:"unitGroups"`
}

func (v *LongVegetationEnforcementPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationEnforcementPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation enforcement preferences", "enforce", "unitGroups"); err != nil {
		return err
	}
	if decoded.UnitGroups < 1 || decoded.UnitGroups > 3 {
		return errors.New("Long Vegetation enforcement requires source unit-group 1, 2 or 3")
	}
	*v = LongVegetationEnforcementPreferenceValues(decoded)
	return nil
}

type LongVegetationEnforcementPreferencesRequest struct {
	Expected LongVegetationEnforcementPreferenceValues `json:"expected"`
	Proposed LongVegetationEnforcementPreferenceValues `json:"proposed"`
}

func (v *LongVegetationEnforcementPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationEnforcementPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation enforcement preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationEnforcementPreferencesRequest(decoded)
	return nil
}

type LongVegetationEnforcementPreferencesReview struct {
	ContextID   string                                    `json:"contextId"`
	Project     string                                    `json:"project"`
	ProjectPath string                                    `json:"projectPath"`
	SU          string                                    `json:"su"`
	SUPath      string                                    `json:"suPath"`
	Values      LongVegetationEnforcementPreferenceValues `json:"values"`
	Printers    vprocore.PrinterObservation               `json:"printers"`
}

type LongVegetationEnforcementPreferencesOutcome struct {
	ContextID    string                       `json:"contextId"`
	Changed      bool                         `json:"changed"`
	Committed    bool                         `json:"committed"`
	ErrorMessage string                       `json:"errorMessage"`
	Printers     *vprocore.PrinterObservation `json:"printers"`
}

type LongVegetationEnforcementPreferencesService struct {
	contexts *vprocore.ContextService
	snapshot vprocore.PublicationReadSnapshotHooks
	printers func(context.Context) (vprocore.PrinterObservation, error)
}

func NewLongVegetationEnforcementPreferencesService(contexts *vprocore.ContextService) *LongVegetationEnforcementPreferencesService {
	return &LongVegetationEnforcementPreferencesService{contexts: contexts, printers: vprocore.ObservePrinters}
}

func (s *LongVegetationEnforcementPreferencesService) helper() vprocore.ReportPreferenceHelper {
	if s == nil || s.printers == nil {
		return vprocore.ReportPreferenceHelper{}
	}
	return vprocore.ReportPreferenceHelper{Contexts: s.contexts, Snapshot: s.snapshot}
}

func (s *LongVegetationEnforcementPreferencesService) GetLongVegetationEnforcementPreferences(ctx context.Context, contextID string) (*LongVegetationEnforcementPreferencesReview, error) {
	h := s.helper()
	return vprocore.WithReportPreferencePlot(ctx, h, contextID, "Long Vegetation enforcement", func(plots *vprocore.PlotService) (*LongVegetationEnforcementPreferencesReview, error) {
		result, err := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, h.Snapshot, func(owner *vprocore.SqliteContext, _ *sql.Tx) (*LongVegetationEnforcementPreferencesReview, error) {
			values, err := ReadLongVegetationEnforcementPreferences(plots.Projects.Preferences, ctx)
			if err != nil {
				return nil, err
			}
			return &LongVegetationEnforcementPreferencesReview{
				ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
				SU: owner.Selection.SU, SUPath: owner.Selection.SUPath, Values: values,
			}, nil
		})
		if err != nil {
			return nil, err
		}
		result.Printers, err = s.printers(ctx)
		if err != nil {
			return nil, fmt.Errorf("Long Vegetation enforcement printer observation unavailable; no values applied: %w", err)
		}
		if err := vprocore.ValidatePrinterObservation(ctx, result.Printers); err != nil {
			return nil, err
		}
		return result, nil
	})
}

func (s *LongVegetationEnforcementPreferencesService) SaveLongVegetationEnforcementPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationEnforcementPreferencesOutcome {
	var observedPrinters *vprocore.PrinterObservation
	receipt := vprocore.SaveOwnedReportPreferences(ctx, s.helper(), contextID, requestJSON, "Long Vegetation enforcement", nil,
		func(plots *vprocore.PlotService, request LongVegetationEnforcementPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
			update, saveErr := CompareAndSetLongVegetationEnforcementPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
			if saveErr != nil {
				return update, saveErr
			}
			printers, err := s.printers(ctx)
			if err == nil {
				err = vprocore.ValidatePrinterObservation(ctx, printers)
			}
			if err != nil {
				if update.Committed {
					return update, fmt.Errorf("Long Vegetation enforcement preferences were committed; do not replay the change; printer refresh unavailable: %w", err)
				}
				return update, fmt.Errorf("Long Vegetation enforcement preferences unchanged; printer refresh unavailable: %w", err)
			}
			observedPrinters = &printers
			return update, nil
		})
	return &LongVegetationEnforcementPreferencesOutcome{
		ContextID: receipt.ContextID, Changed: receipt.Changed, Committed: receipt.Committed,
		ErrorMessage: receipt.ErrorMessage, Printers: observedPrinters,
	}
}

// 11. Long Vegetation Report Unit Preferences

type LongVegetationUnitPreferenceValues struct {
	UnitGroups int `json:"unitGroups"`
}

func (v *LongVegetationUnitPreferenceValues) UnmarshalJSON(data []byte) error {
	type plain LongVegetationUnitPreferenceValues
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation report unit preferences", "unitGroups"); err != nil {
		return err
	}
	if decoded.UnitGroups < 1 || decoded.UnitGroups > 3 {
		return errors.New("Long Vegetation report units require source choice 1, 2 or 3")
	}
	*v = LongVegetationUnitPreferenceValues(decoded)
	return nil
}

type LongVegetationUnitPreferencesRequest struct {
	Expected LongVegetationUnitPreferenceValues `json:"expected"`
	Proposed LongVegetationUnitPreferenceValues `json:"proposed"`
}

func (v *LongVegetationUnitPreferencesRequest) UnmarshalJSON(data []byte) error {
	type plain LongVegetationUnitPreferencesRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, "Long Vegetation report unit preference save", "expected", "proposed"); err != nil {
		return err
	}
	*v = LongVegetationUnitPreferencesRequest(decoded)
	return nil
}

type LongVegetationUnitAvailability struct {
	SiteUnitTable  bool `json:"siteUnitTable"`
	SelectedFields bool `json:"selectedFields"`
	None           bool `json:"none"`
}

func (a LongVegetationUnitAvailability) allows(group int) bool {
	switch group {
	case 1:
		return a.SiteUnitTable
	case 2:
		return a.SelectedFields
	case 3:
		return a.None
	default:
		return false
	}
}

type LongVegetationUnitPreferencesReview struct {
	ContextID    string                             `json:"contextId"`
	Project      string                             `json:"project"`
	ProjectPath  string                             `json:"projectPath"`
	SU           string                             `json:"su"`
	SUPath       string                             `json:"suPath"`
	Values       LongVegetationUnitPreferenceValues `json:"values"`
	Availability LongVegetationUnitAvailability     `json:"availability"`
}

type LongVegetationUnitPreferencesOutcome struct {
	ContextID    string `json:"contextId"`
	Changed      bool   `json:"changed"`
	Committed    bool   `json:"committed"`
	ErrorMessage string `json:"errorMessage"`
}

type LongVegetationUnitPreferencesService struct {
	contexts              *vprocore.ContextService
	snapshot              vprocore.PublicationReadSnapshotHooks
	beforeSelectedUnitCAS func()
}

func NewLongVegetationUnitPreferencesService(contexts *vprocore.ContextService) *LongVegetationUnitPreferencesService {
	return &LongVegetationUnitPreferencesService{contexts: contexts}
}

func (s *LongVegetationUnitPreferencesService) helper() vprocore.ReportPreferenceHelper {
	if s == nil {
		return vprocore.ReportPreferenceHelper{}
	}
	var checkScope func(string) error
	if s.contexts != nil {
		checkScope = func(cid string) error { return vprocore.RequireSelectedListReportScope(s.contexts, cid) }
	}
	return vprocore.ReportPreferenceHelper{
		Contexts:   s.contexts,
		Snapshot:   s.snapshot,
		CheckScope: checkScope,
	}
}

func (s *LongVegetationUnitPreferencesService) availability(selectedFields bool) LongVegetationUnitAvailability {
	return LongVegetationUnitAvailability{SiteUnitTable: true, SelectedFields: selectedFields, None: true}
}

func (s *LongVegetationUnitPreferencesService) GetLongVegetationUnitPreferences(ctx context.Context, contextID string) (*LongVegetationUnitPreferencesReview, error) {
	return vprocore.GetOwnedReportPreferences(ctx, s.helper(), contextID, "Long Vegetation report unit",
		func(plots *vprocore.PlotService, owner *vprocore.SqliteContext, tx *sql.Tx) (*LongVegetationUnitPreferencesReview, error) {
			values, err := ReadLongVegetationUnitPreferences(plots.Projects.Preferences, ctx)
			if err != nil {
				return nil, err
			}
			selectedFields, err := SelectedUnitAvailability(s.contexts, ctx, plots, tx)
			if err != nil {
				return nil, err
			}
			return &LongVegetationUnitPreferencesReview{
				ContextID: contextID, Project: owner.Selection.Project, ProjectPath: owner.Selection.ProjectPath,
				SU: owner.Selection.SU, SUPath: owner.Selection.SUPath,
				Values: values, Availability: s.availability(selectedFields),
			}, nil
		})
}

func (s *LongVegetationUnitPreferencesService) SaveLongVegetationUnitPreferences(ctx context.Context, contextID, requestJSON string) *LongVegetationUnitPreferencesOutcome {
	h := s.helper()
	out := LongVegetationUnitPreferencesOutcome(vprocore.RunReportPreferenceSave(ctx, h, contextID, requestJSON, "Long Vegetation report unit",
		func(plots *vprocore.PlotService, request LongVegetationUnitPreferencesRequest) (vprocore.ReportPreferenceUpdate, error) {
			if err := vprocore.RequireSelectedListReportScope(s.contexts, contextID); err != nil {
				return vprocore.ReportPreferenceUpdate{}, err
			}
			if request.Expected.UnitGroups != 2 && request.Proposed.UnitGroups == 2 {
				var captured vprocore.ReportPreferenceUpdate
				_, snapErr := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, h.Snapshot, func(owner *vprocore.SqliteContext, tx *sql.Tx) (struct{}, error) {
					if err := vprocore.RequireSelectedListReportScope(s.contexts, contextID); err != nil {
						return struct{}{}, err
					}
					ledger := selectedUnitSelections(s.contexts)
					ledger.Mu.Lock()
					defer ledger.Mu.Unlock()
					values, err := plots.Projects.Preferences.Snapshot()
					if err != nil {
						return struct{}{}, err
					}
					if _, err := validateSelectedUnitApproval(ctx, contextID, owner, tx, values, ledger.Entries[contextID]); err != nil {
						return struct{}{}, err
					}
					planned, err := selectedUnitConfigForChoice(values, 2)
					if err != nil {
						return struct{}{}, err
					}
					if s.beforeSelectedUnitCAS != nil {
						s.beforeSelectedUnitCAS()
					}
					update, err := CompareAndSetReviewedLongVegetationUnitPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed, func(current vprocore.ConfigValues) error {
						currentPlan, err := selectedUnitConfigForChoice(current, 2)
						if err != nil {
							return err
						}
						if !reflect.DeepEqual(planned, currentPlan) {
							return errors.New("selected report unit configuration changed since Build; rebuild explicitly before Save")
						}
						return nil
					})
					captured = update
					return struct{}{}, err
				})
				return captured, snapErr
			}
			if _, readErr := vprocore.WithOwnedPreferenceSnapshot(ctx, plots, h.Snapshot, func(*vprocore.SqliteContext, *sql.Tx) (struct{}, error) {
				return struct{}{}, nil
			}); readErr != nil {
				return vprocore.ReportPreferenceUpdate{}, readErr
			}
			owner := plots.Projects.Sqlite
			unlock, err := owner.AcquireMutex(ctx)
			if err != nil {
				return vprocore.ReportPreferenceUpdate{}, err
			}
			defer unlock()
			if err := vprocore.ProfileOwnedFiles(owner); err != nil {
				return vprocore.ReportPreferenceUpdate{}, err
			}
			if err := vprocore.RequireSelectedListReportScope(s.contexts, contextID); err != nil {
				return vprocore.ReportPreferenceUpdate{}, err
			}
			if request.Expected.UnitGroups != request.Proposed.UnitGroups && !s.availability(false).allows(request.Proposed.UnitGroups) {
				return vprocore.ReportPreferenceUpdate{}, fmt.Errorf("Long Vegetation report unit choice %d is unavailable in this session; saved LVUnitGroups was not reset", request.Proposed.UnitGroups)
			}
			return CompareAndSetLongVegetationUnitPreferences(plots.Projects.Preferences, ctx, request.Expected, request.Proposed)
		}))
	return &out
}
