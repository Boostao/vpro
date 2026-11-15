package sourceform

import (
	"context"
	"fmt"
	"regexp"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

var siviParentTimestampPattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?$`)

func ValidateSIVIParentDateTimestamp(value *string) error {
	if value == nil {
		return nil
	}
	if !siviParentTimestampPattern.MatchString(*value) {
		return fmt.Errorf("Date requires YYYY-MM-DD HH:MM:SS[.fraction] without a timezone")
	}
	parsed, err := time.Parse("2006-01-02 15:04:05.999999999", *value)
	if err != nil {
		return fmt.Errorf("Date must be a valid calendar/time value: %w", err)
	}
	if parsed.Year() < 100 {
		return fmt.Errorf("Date year must be between 0100 and 9999")
	}
	return nil
}

func PlanSIVIParentText(ctx context.Context, contextID, project, plot string, env, admin vprocore.ProjectMetadataTable, edits []SiviParentScalarEdit) ([]SiviParentScalarAssignment, error) {
	owners := map[string]string{"SV_PolygonNumber": "Env", "SV_CanopyComposition": "Env"}
	return planSIVIParentCells(ctx, contextID, project, plot, env, admin, edits, owners, ValidateSIVIParentText)
}

func ValidateSIVIParentText(column string, value vprocore.ProjectMetadataCell) error {
	if value.Storage != "null" && value.Storage != "text" {
		return fmt.Errorf("SIVI %s requires explicit NULL or nonempty TEXT storage", column)
	}
	maximum := 25
	if column == "SV_CanopyComposition" {
		maximum = 50
	}
	return sqlutil.ValidateSiteCodeText(column, value.Text, maximum)
}

func PlanSIVIParentCategorical(ctx context.Context, contextID, project, plot string, env, admin vprocore.ProjectMetadataTable, edits []SiviParentScalarEdit) ([]SiviParentScalarAssignment, error) {
	owners := map[string]string{"SnowCoverregime": "Env", "SV_RootZoneTexture": "Env", "SV_AhorizonType": "Env"}
	return planSIVIParentCells(ctx, contextID, project, plot, env, admin, edits, owners, ValidateSIVIParentCategorical)
}

func ValidateSIVIParentCategorical(column string, value vprocore.ProjectMetadataCell) error {
	if value.Storage != "null" && value.Storage != "text" {
		return fmt.Errorf("SIVI %s requires explicit NULL or TEXT storage", column)
	}
	if value.Text != nil && *value.Text == "" {
		return nil
	}
	maximum := 1
	switch column {
	case "SV_RootZoneTexture":
		maximum = 100
	case "SV_AhorizonType":
		maximum = 5
	}
	return sqlutil.ValidateSiteCodeText(column, value.Text, maximum)
}

func ValidateSourceParentBooleanAssignments(assignments []SiviParentScalarAssignment) error {
	for _, assignment := range assignments {
		if err := vprocore.ValidateSourceParentBooleanNull(assignment.Column,
			assignment.Before.Storage == "null", assignment.After.Storage == "null"); err != nil {
			return err
		}
	}
	return nil
}
