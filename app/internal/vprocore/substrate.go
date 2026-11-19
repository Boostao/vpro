package vprocore

import (
	"database/sql"
	"fmt"
	"math"
)

// ValidateSingleRangeChange — Retain finite imported overflow only when it equals the actual stored value.
// New values preserve float64 precision within the native SINGLE range.
func ValidateSingleRangeChange(property string, before, after *float64) error {
	if after == nil {
		return nil
	}
	if math.IsNaN(*after) || math.IsInf(*after, 0) {
		return fmt.Errorf("property %q must be finite", property)
	}
	if SameHeightValue(before, after) {
		return nil
	}
	if math.Abs(*after) > math.MaxFloat32 {
		return fmt.Errorf("property %q exceeds physical Single range", property)
	}
	return nil
}

type substrateHeaderField struct {
	Property string   `json:"-" yaml:"-"`
	Column   string   `json:"-" yaml:"-"`
	Value    *float64 `json:"-" yaml:"-"`
}

func SubstrateHeaderFields(h FS882Header) []substrateHeaderField {
	return []substrateHeaderField{
		{"substrateBedRock", "SubstrateBedRock", h.SubstrateBedRock},
		{"substrateDecWood", "SubstrateDecWood", h.SubstrateDecWood},
		{"substrateMineralSoil", "SubstrateMineralSoil", h.SubstrateMineralSoil},
		{"substrateOrganicMatter", "SubstrateOrganicMatter", h.SubstrateOrganicMatter},
		{"substrateRocks", "SubstrateRocks", h.SubstrateRocks},
		{"substrateWater", "SubstrateWater", h.SubstrateWater},
	}
}

func isSubstrateProperty(property string) bool {
	for _, field := range SubstrateHeaderFields(FS882Header{}) {
		if property == field.Property {
			return true
		}
	}
	return false
}

func ValidateSubstrateHeaderValuesWithBounds(h FS882Header, old *FS882Header, enforcePercentBounds bool) error {
	previous := SubstrateHeaderFields(FS882Header{})
	if old != nil {
		previous = SubstrateHeaderFields(*old)
	}
	for i, field := range SubstrateHeaderFields(h) {
		if err := ValidateSingleRangeChange(field.Property, previous[i].Value, field.Value); err != nil {
			return err
		}
		if enforcePercentBounds && field.Value != nil && !SameHeightValue(previous[i].Value, field.Value) {
			if *field.Value < 0 || *field.Value > 100 {
				return fmt.Errorf("%s must be between 0%% and 100%% (got %v)", field.Column, *field.Value)
			}
		}
	}
	return nil
}

func ValidateSubstrateHeaderValues(h FS882Header, old *FS882Header) error {
	return ValidateSubstrateHeaderValuesWithBounds(h, old, false)
}

func ValidateSubstrateHeaderBeforeTransactionWithBounds(db *sql.DB, project string, h FS882Header, mode headerSaveMode, enforcePercentBounds bool) error {
	if err := ValidateSubstrateHeaderValuesWithBounds(h, nil, enforcePercentBounds); err == nil {
		return nil
	} else if mode == headerCreate {
		return err
	}
	caps, err := HeaderCapabilities(db, project)
	if err != nil {
		return err
	}
	for _, field := range SubstrateHeaderFields(h) {
		checkOne := func(before *float64) error {
			if err := ValidateSingleRangeChange(field.Property, before, field.Value); err != nil {
				return err
			}
			if enforcePercentBounds && field.Value != nil && !SameHeightValue(before, field.Value) && (*field.Value < 0 || *field.Value > 100) {
				return fmt.Errorf("%s must be between 0%% and 100%% (got %v)", field.Column, *field.Value)
			}
			return nil
		}
		if err := checkOne(nil); err == nil {
			continue
		}
		if math.IsNaN(*field.Value) || math.IsInf(*field.Value, 0) {
			return ValidateSingleRangeChange(field.Property, nil, field.Value)
		}
		if !caps[field.Property] {
			return fmt.Errorf("unsupported header property %q in active project", field.Property)
		}
		var previous *float64
		err := db.QueryRow(`SELECT `+QuoteHeaderIdentifier(field.Column)+` FROM `+
			QuoteHeaderIdentifier(project+"_Env")+` WHERE `+ExactTextPlotPredicate(`"PlotNumber"`), h.PlotNumber, h.PlotNumber).Scan(&previous)
		if err == sql.ErrNoRows {
			return checkOne(nil)
		}
		if err != nil {
			return err
		}
		if err := checkOne(previous); err != nil {
			return err
		}
	}
	return nil
}

func ValidateSubstrateHeaderBeforeTransaction(db *sql.DB, project string, h FS882Header, mode headerSaveMode) error {
	return ValidateSubstrateHeaderBeforeTransactionWithBounds(db, project, h, mode, false)
}

func validateSubstrateRestoreValue(table, column string, value any) error {
	if table != "Env" {
		return nil
	}
	for _, field := range SubstrateHeaderFields(FS882Header{}) {
		if column != field.Column {
			continue
		}
		if value == nil {
			return nil
		}
		number, ok := value.(float64)
		if !ok {
			return fmt.Errorf("%s audit restore requires a nullable number", column)
		}
		return ValidateSingleRangeChange(field.Property, nil, &number)
	}
	return nil
}
