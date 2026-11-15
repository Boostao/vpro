package sourceform

import (
	"github.com/boostao/vpro/app/internal/vprocore"
)

func ValidateSourceParentBooleanAssignments(assignments []SiviParentScalarAssignment) error {
	for _, assignment := range assignments {
		if err := vprocore.ValidateSourceParentBooleanNull(assignment.Column,
			assignment.Before.Storage == "null", assignment.After.Storage == "null"); err != nil {
			return err
		}
	}
	return nil
}
