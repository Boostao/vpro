package vprocore

import (
	"github.com/boostao/vpro/app/internal/sqlutil"
)

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"reflect"
)

type SoilTextUpdate struct {
	Value    *string `json:"value"`
	Expected *string `json:"expected"`
}

func decodeChildChange(data []byte, target any) error {
	var properties map[string]json.RawMessage
	if err := json.Unmarshal(data, &properties); err != nil {
		return err
	}
	if _, present := properties["value"]; !present {
		return errors.New("child change requires explicit value and expected")
	}
	if _, present := properties["expected"]; !present {
		return errors.New("child change requires explicit value and expected")
	}
	return json.Unmarshal(data, target)
}

func (change *SoilTextUpdate) UnmarshalJSON(data []byte) error {
	type plain SoilTextUpdate
	if err := sqlutil.ValidateJSONTextProperties(data, map[string]string{"value": "Soil value", "expected": "Soil expected"}); err != nil {
		return err
	}
	return decodeChildChange(data, (*plain)(change))
}

type SoilNumberUpdate struct {
	Value    *float64 `json:"value"`
	Expected *float64 `json:"expected"`
}

func (change *SoilNumberUpdate) UnmarshalJSON(data []byte) error {
	type plain SoilNumberUpdate
	return decodeChildChange(data, (*plain)(change))
}

type SoilRecordUpdate struct {
	Kind    string                      `json:"kind"`
	ID      int                         `json:"id"`
	Text    map[string]SoilTextUpdate   `json:"text"`
	Numbers map[string]SoilNumberUpdate `json:"numbers"`
}

func (update *SoilRecordUpdate) UnmarshalJSON(data []byte) error {
	type plain SoilRecordUpdate
	var properties map[string]json.RawMessage
	if err := json.Unmarshal(data, &properties); err != nil {
		return err
	}
	for _, name := range []string{"id", "kind"} {
		if value, present := properties[name]; !present || string(value) == "null" {
			return errors.New("soil draft requires an explicit kind and signed32 identity")
		}
	}
	return json.Unmarshal(data, (*plain)(update))
}

func soilPatchNumber(kind, column string, number *float64) (any, reflect.Kind, error) {
	scalar := reflect.Float64
	if SoilChildIntegerColumns[kind][column] {
		scalar = reflect.Int
	}
	if number == nil {
		return nil, scalar, nil
	}
	if math.IsNaN(*number) || math.IsInf(*number, 0) {
		return nil, scalar, fmt.Errorf("%s.%s requires a finite number", kind, column)
	}
	if scalar == reflect.Int {
		if math.Trunc(*number) != *number || math.Abs(*number) > 9007199254740991 {
			return nil, scalar, fmt.Errorf("%s.%s requires an exact integer", kind, column)
		}
		return int(*number), scalar, nil
	}
	return *number, scalar, nil
}

func (s *PlotService) UpdateSoilRecords(plot string, updates []SoilRecordUpdate) error {
	patches := make([]ChildRecordPatch, 0, len(updates))
	for _, update := range updates {
		if update.Kind != "Humus" && update.Kind != "Mineral" {
			return fmt.Errorf("unsupported soil draft kind %q", update.Kind)
		}
		patch := ChildRecordPatch{Kind: update.Kind, Id: update.ID, Cells: map[string]ChildExpectedValue{}}
		for property, change := range update.Text {
			patch.Cells[property] = ChildExpectedValue{OtherNullable(change.Expected), OtherNullable(change.Value), reflect.String}
		}
		for property, change := range update.Numbers {
			if _, present := patch.Cells[property]; present {
				return fmt.Errorf("soil property %q has conflicting change types", property)
			}
			var column string
			for _, field := range ChildFields[update.Kind] {
				if ChildJSONKey(ChildPatchShape(update.Kind), field) == property {
					column = field.Column
					break
				}
			}
			expected, scalar, err := soilPatchNumber(update.Kind, column, change.Expected)
			if err != nil {
				return err
			}
			value, _, err := soilPatchNumber(update.Kind, column, change.Value)
			if err != nil {
				return err
			}
			patch.Cells[property] = ChildExpectedValue{expected, value, scalar}
		}
		var depthHorizonChanged, coarseFragsChanged bool
		for _, prop := range []string{"horizon", "upperDepth", "lowerDepth"} {
			if cell, ok := patch.Cells[prop]; ok && !reflect.DeepEqual(cell.Expected, cell.Value) {
				depthHorizonChanged = true
				break
			}
		}
		if update.Kind == "Mineral" {
			for _, prop := range []string{"percentCoarseFragsGravel", "percentCoarseFragsCobbles", "percentCoarseFragsStones", "percentCoarseFragsTotal"} {
				if cell, ok := patch.Cells[prop]; ok && !reflect.DeepEqual(cell.Expected, cell.Value) {
					coarseFragsChanged = true
					break
				}
			}
		}
		if depthHorizonChanged || coarseFragsChanged {
			kind := update.Kind
			id := update.ID
			cells := patch.Cells
			checkDepth := depthHorizonChanged
			checkCF := coarseFragsChanged
			patch.Validate = func(tx *sql.Tx, table, plot string) error {
				if checkDepth {
					var curHorizon sql.NullString
					var curUpper, curLower sql.NullFloat64
					if err := tx.QueryRow(`SELECT "Horizon", "UpperDepth", "LowerDepth" FROM `+table+` WHERE "PlotNumber" = ? AND "ID" = ?`, plot, id).
						Scan(&curHorizon, &curUpper, &curLower); err != nil {
						return err
					}
					var effHorizon *string
					if curHorizon.Valid {
						h := curHorizon.String
						effHorizon = &h
					}
					var effUpper, effLower *float64
					if curUpper.Valid {
						u := curUpper.Float64
						effUpper = &u
					}
					if curLower.Valid {
						l := curLower.Float64
						effLower = &l
					}
					if cell, ok := cells["horizon"]; ok {
						if cell.Value == nil {
							effHorizon = nil
						} else if h, ok := cell.Value.(string); ok {
							effHorizon = &h
						}
					}
					if cell, ok := cells["upperDepth"]; ok {
						if cell.Value == nil {
							effUpper = nil
						} else if u, ok := cell.Value.(float64); ok {
							effUpper = &u
						}
					}
					if cell, ok := cells["lowerDepth"]; ok {
						if cell.Value == nil {
							effLower = nil
						} else if l, ok := cell.Value.(float64); ok {
							effLower = &l
						}
					}
					if err := ValidateSoilHorizonDepthSign(kind, effHorizon, effUpper, effLower); err != nil {
						return fmt.Errorf("%s identity (%q, %d): %w", kind, plot, id, err)
					}
				}
				if checkCF {
					var curG, curC, curS, curTot sql.NullInt64
					if err := tx.QueryRow(`SELECT "PercentCoarseFragsGravel", "PercentCoarseFragsCobbles", "PercentCoarseFragsStones", "PercentCoarseFragsTotal" FROM `+table+` WHERE "PlotNumber" = ? AND "ID" = ?`, plot, id).
						Scan(&curG, &curC, &curS, &curTot); err != nil {
						return err
					}
					resolveInt := func(cur sql.NullInt64, prop string) *int {
						if cell, ok := cells[prop]; ok {
							if cell.Value == nil {
								return nil
							}
							if n, ok := cell.Value.(int); ok {
								return &n
							}
						}
						if cur.Valid {
							n := int(cur.Int64)
							return &n
						}
						return nil
					}
					effG := resolveInt(curG, "percentCoarseFragsGravel")
					effC := resolveInt(curC, "percentCoarseFragsCobbles")
					effS := resolveInt(curS, "percentCoarseFragsStones")
					effTot := resolveInt(curTot, "percentCoarseFragsTotal")
					if err := ValidateMineralCoarseFragments(effG, effC, effS, effTot); err != nil {
						return fmt.Errorf("%s identity (%q, %d): %w", kind, plot, id, err)
					}
				}
				return nil
			}
		}
		patches = append(patches, patch)
	}
	return s.UpdateChildPatches(plot, patches)
}
