package vprocore

import (
	"database/sql"
	"errors"
	"fmt"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

func validateCodeHeaderValues(h FS882Header, old *FS882Header, fields func(FS882Header) []BecHeaderField, rejectUnchangedMalformedText bool) error {
	var previous []BecHeaderField
	if old != nil {
		previous = fields(*old)
	}
	for i, field := range fields(h) {
		if rejectUnchangedMalformedText && field.Value != nil && !utf8.ValidString(*field.Value) {
			return sqlutil.ValidateSiteCodeText(field.Name, field.Value, field.Maximum)
		}
		if old != nil && SameSiteCode(previous[i].Value, field.Value) {
			continue
		}
		if err := sqlutil.ValidateSiteCodeText(field.Name, field.Value, field.Maximum); err != nil {
			return err
		}
	}
	return nil
}

func validateCodeHeaderBeforeTransaction(db *sql.DB, project string, h FS882Header, mode headerSaveMode, validate func(FS882Header, *FS882Header) error) error {
	if mode == headerCreate {
		return validate(h, nil)
	}
	caps, err := HeaderCapabilities(db, project)
	if err != nil {
		return err
	}
	old, err := ReadHeader(db, project, h.PlotNumber, caps)
	if errors.Is(err, sql.ErrNoRows) {
		old = nil
	} else if err != nil {
		return err
	}
	return validate(h, old)
}

func validateCodeRestoreValue(table, column string, value any, fields []BecHeaderField) error {
	for _, field := range fields {
		if field.Table != table || field.Name != column {
			continue
		}
		if value == nil {
			return nil
		}
		text, ok := value.(string)
		if !ok {
			return fmt.Errorf("%s audit restore requires a nullable string", column)
		}
		return sqlutil.ValidateSiteCodeText(column, &text, field.Maximum)
	}
	return nil
}

func RegionHeaderFields(h FS882Header) []BecHeaderField {
	return []BecHeaderField{
		{"FSRegionDistrict", "fsRegionDistrict", "Env", 7, h.FSRegionDistrict},
		{"Ecosection", "ecosection", "Env", 3, h.Ecosection},
	}
}

func isRegionProperty(property string) bool {
	return property == "fsRegionDistrict" || property == "ecosection"
}

func validateRegionHeaderValues(h FS882Header, old *FS882Header) error {
	return validateCodeHeaderValues(h, old, RegionHeaderFields, true)
}

func validateRegionHeaderBeforeTransaction(db *sql.DB, project string, h FS882Header, mode headerSaveMode) error {
	return validateCodeHeaderBeforeTransaction(db, project, h, mode, validateRegionHeaderValues)
}

func ValidateRegionRestoreValue(table, column string, value any) error {
	return validateCodeRestoreValue(table, column, value, RegionHeaderFields(FS882Header{}))
}

func SoilHeaderFields(h FS882Header) []BecHeaderField {
	return []BecHeaderField{
		{"SoilClassGroup", "soilClassGroup", "Env", 4, h.SoilClassGroup},
		{"SoilClassSubGroup", "soilClassSubGroup", "Env", 4, h.SoilClassSubGroup},
	}
}

func isSoilProperty(property string) bool {
	return property == "soilClassGroup" || property == "soilClassSubGroup"
}

func validateSoilHeaderValues(h FS882Header, old *FS882Header) error {
	return validateCodeHeaderValues(h, old, SoilHeaderFields, false)
}

func validateSoilHeaderBeforeTransaction(db *sql.DB, project string, h FS882Header, mode headerSaveMode) error {
	return validateCodeHeaderBeforeTransaction(db, project, h, mode, validateSoilHeaderValues)
}

func ValidateSoilRestoreValue(table, column string, value any) error {
	return validateCodeRestoreValue(table, column, value, SoilHeaderFields(FS882Header{}))
}

func GeologyHeaderFields(h FS882Header) []BecHeaderField {
	return []BecHeaderField{
		{"BedrockGeology1", "bedrockGeology1", "Env", 4, h.BedrockGeology1},
		{"BedrockGeology2", "bedrockGeology2", "Env", 4, h.BedrockGeology2},
		{"BedrockGeology3", "bedrockGeology3", "Env", 4, h.BedrockGeology3},
	}
}

func isGeologyProperty(property string) bool {
	return property == "bedrockGeology1" || property == "bedrockGeology2" || property == "bedrockGeology3"
}

func validateGeologyHeaderValues(h FS882Header, old *FS882Header) error {
	return validateCodeHeaderValues(h, old, GeologyHeaderFields, false)
}

func validateGeologyHeaderBeforeTransaction(db *sql.DB, project string, h FS882Header, mode headerSaveMode) error {
	return validateCodeHeaderBeforeTransaction(db, project, h, mode, validateGeologyHeaderValues)
}

func ValidateGeologyRestoreValue(table, column string, value any) error {
	return validateCodeRestoreValue(table, column, value, GeologyHeaderFields(FS882Header{}))
}
