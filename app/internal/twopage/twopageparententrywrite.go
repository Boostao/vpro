package twopage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type TwoPageEntryApproval func(*sql.Tx, *sourceform.SourceParentProjection, []sourceform.SourceParentScalarAssignment) error

type TwoPageEntryLifecycle = sourceform.SourceParentEntryLifecycle

func TwoPageEntryHistory(form string, masterAllowed bool) (sourceform.SourceParentHistoryDomain, error) {
	return twoPageEntryHistoryAuthority(form, func() bool { return masterAllowed })
}

func twoPageEntryHistoryAuthority(form string, masterAllowed func() bool) (sourceform.SourceParentHistoryDomain, error) {
	history, err := twoPageParentHistory(form, "Entry", "two-page complete entry",
		func(ctx context.Context, original *sourceform.SourceParentProjection, edits []sourceform.SourceParentScalarEdit) ([]sourceform.SourceParentScalarAssignment, error) {
			return PlanTwoPageEntryProjection(ctx, original, edits, masterAllowed())
		})
	if err != nil {
		return sourceform.SourceParentHistoryDomain{}, err
	}
	history.Assignments = func(ctx context.Context, event sourceform.SourceParentHistory, project, plot string) ([]sourceform.SourceParentScalarAssignment, error) {
		return twoPageEntryHistoryAssignments(ctx, form, masterAllowed(), event, project, plot)
	}
	return history, nil
}

// WriteTwoPageEntry — This private boundary requires independent reference/role approval before publication.
func WriteTwoPageEntry(s *vprocore.ContextService, ctx context.Context, contextID, plot, form string, original *sourceform.SourceParentProjection,
	edits []sourceform.SourceParentScalarEdit, masterAllowed bool, approve TwoPageEntryApproval) (*sourceform.SourceParentWriteResult, error) {
	return WriteTwoPageEntryWithLifecycle(s, ctx, contextID, plot, form, original, edits, masterAllowed, approve, TwoPageEntryLifecycle{})
}

func WriteTwoPageEntryWithLifecycle(s *vprocore.ContextService, ctx context.Context, contextID, plot, form string, original *sourceform.SourceParentProjection,
	edits []sourceform.SourceParentScalarEdit, masterAllowed bool, approve TwoPageEntryApproval, lifecycle TwoPageEntryLifecycle) (*sourceform.SourceParentWriteResult, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if approve == nil {
		return nil, errors.New("two-page complete entry requires independent reference and role approval")
	}
	authorizedMaster := false
	history, err := twoPageEntryHistoryAuthority(form, func() bool { return authorizedMaster })
	if err != nil {
		return nil, err
	}
	read, err := TwoPageParentWriteReader(form)
	if err != nil {
		return nil, err
	}
	var requestPlots *vprocore.PlotService
	var entryPlan []sourceform.SourceParentScalarEdit
	hooks := sourceform.SourceParentWriteHooks{
		Authorize: func(plots *vprocore.PlotService) error {
			authorizedMaster = masterAllowed && vprocore.MasterBECAllowed(plots.CurrentUser)
			requestPlots = plots
			return nil
		},
		Read: read,
		Plan: func(tx *sql.Tx, observed *sourceform.SourceParentProjection) ([]sourceform.SourceParentScalarAssignment, error) {
			assignments, err := PlanTwoPageEntryProjection(ctx, observed, edits, authorizedMaster)
			if err != nil {
				return nil, err
			}
			if err := sourceform.ValidateSourceParentBooleanAssignments(assignments); err != nil {
				return nil, fmt.Errorf("two-page complete entry: %w", err)
			}
			if err := approve(tx, observed, assignments); err != nil {
				return nil, fmt.Errorf("two-page complete entry approval: %w", err)
			}
			entryPlan = make([]sourceform.SourceParentScalarEdit, 0, len(assignments))
			for _, assignment := range assignments {
				entryPlan = append(entryPlan, sourceform.SourceParentScalarEdit{ContextID: assignment.ContextID, Table: assignment.Table, RowID: assignment.RowID,
					Column: assignment.Column, Expected: vprocore.CloneSiteUnitCell(assignment.Before), Value: vprocore.CloneSiteUnitCell(assignment.After)})
			}
			return assignments, nil
		},
	}
	if lifecycle.Prepare != nil {
		hooks.Prepare = func(conn *sql.Conn) (func(), error) {
			if requestPlots == nil {
				return nil, errors.New("complete-entry preparation requires the immutable owned request")
			}
			return lifecycle.Prepare(requestPlots, conn)
		}
	}
	if lifecycle.Verify != nil {
		hooks.Verify = func(tx *sql.Tx) error {
			if requestPlots == nil {
				return errors.New("complete-entry verification requires the immutable owned request")
			}
			return lifecycle.Verify(requestPlots, tx)
		}
	}
	hooks.Decorate = func(event *sourceform.SourceParentHistory) {
		event.EntryPlan = entryPlan
		if lifecycle.Decorate != nil {
			lifecycle.Decorate(event)
		}
	}
	return sourceform.WriteSourceParentPlannedWithHooks(s, ctx, contextID, plot, original, history, nil, hooks)
}

func RestoreTwoPageEntry(s *vprocore.ContextService, ctx context.Context, contextID, plot, form, historyID string,
	action vprocore.AuditRestoreAction, masterAllowed bool) (*vprocore.AuditRestoreResult, error) {
	authorizedMaster := false
	history, err := twoPageEntryHistoryAuthority(form, func() bool { return authorizedMaster })
	if err != nil {
		return nil, err
	}
	read, err := TwoPageParentWriteReader(form)
	if err != nil {
		return nil, err
	}
	result, err := sourceform.RestoreSourceParentHistoryAuthorized(s, ctx, contextID, plot, historyID, action, history, read,
		func(plots *vprocore.PlotService) error {
			authorizedMaster = masterAllowed && vprocore.MasterBECAllowed(plots.CurrentUser)
			return nil
		})
	if err != nil {
		return nil, fmt.Errorf("two-page complete entry restoration: %w", err)
	}
	return result, nil
}
