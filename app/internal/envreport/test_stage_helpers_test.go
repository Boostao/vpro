package envreport

import (
	"context"
	"database/sql"
	"errors"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func planSiteUnitSummary(ctx context.Context, project, suName string, method, maxJoinedRows int,
	env, admin, su, master vprocore.ProjectMetadataTable) (SiteUnitSummaryReport, error) {
	return planSiteUnitSummaryWithSource(ctx, project, suName, siteUnitDetailSelectedSU, method, maxJoinedRows, env, admin, su, master)
}

func ReadSiteUnitDetailNormalSUScope(s *vprocore.ContextService, ctx context.Context, contextID string,
	maxJoinedRows int, hooks vprocore.PublicationReadSnapshotHooks) (siteUnitDetailOwnedScope, error) {
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (siteUnitDetailOwnedScope, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, hooks, func(owner *vprocore.SqliteContext, tx *sql.Tx) (siteUnitDetailOwnedScope, error) {
			if owner.Selection.SU == "None" {
				return siteUnitDetailOwnedScope{}, errors.New("site unit detail scope requires an explicitly selected normal SU")
			}
			env, err := vprocore.ReadPhysicalLocationTable(ctx, tx, "project", owner.Selection.Project+"_Env")
			if err != nil {
				return siteUnitDetailOwnedScope{}, err
			}
			admin, err := vprocore.ReadPhysicalLocationTable(ctx, tx, "project", owner.Selection.Project+"_Admin")
			if err != nil {
				return siteUnitDetailOwnedScope{}, err
			}
			su, err := vprocore.ReadPhysicalLocationTable(ctx, tx, "su", owner.Selection.SU+"_SU")
			if err != nil {
				return siteUnitDetailOwnedScope{}, err
			}
			scope, err := prepareSiteUnitDetailScope(ctx, owner.Selection.Project, owner.Selection.SU,
				siteUnitDetailSelectedSU, maxJoinedRows, env, admin, su)
			if err != nil {
				return siteUnitDetailOwnedScope{}, err
			}
			return siteUnitDetailOwnedScope{contextID, owner.Selection.ProjectPath, owner.Selection.SUPath, scope}, nil
		})
	})
}

func prepareSiteUnitSummaryLifeformWorkbook(ctx context.Context, input siteUnitQuickVegetationInput) (siteUnitSummaryWorkbook, error) {
	if ctx == nil {
		return siteUnitSummaryWorkbook{}, errors.New("Summary lifeform workbook requires a context")
	}
	preview, err := siteUnitSummaryLifeformPreview(ctx, input)
	if err != nil {
		return siteUnitSummaryWorkbook{}, err
	}
	return prepareSiteUnitSummaryWorkbookProjection(ctx, preview, 2, nil)
}

func prepareSiteUnitSummarySpeciesWorkbook(ctx context.Context, input siteUnitQuickVegetationInput,
	request SiteUnitSpeciesListRequest) (siteUnitSummaryWorkbook, error) {
	preview, err := siteUnitSummarySpeciesPreview(ctx, input, request)
	if err != nil {
		return siteUnitSummaryWorkbook{}, err
	}
	return prepareSiteUnitSummaryWorkbookProjection(ctx, preview.Environment, request.OrderBy, &preview)
}

func ReadSiteUnitSummaryWorkbookInput(s *vprocore.ContextService, ctx context.Context, contextID string, method int,
	hooks vprocore.PublicationReadSnapshotHooks) (siteUnitSummaryWorkbookInput, error) {
	if ctx == nil {
		return siteUnitSummaryWorkbookInput{}, errors.New("Summary Environment workbook requires a context")
	}
	if err := ctx.Err(); err != nil {
		return siteUnitSummaryWorkbookInput{}, err
	}
	if s == nil || s.Projects == nil || s.Projects.Sqlite == nil || s.Plots == nil {
		return siteUnitSummaryWorkbookInput{}, errors.New("Summary Environment workbook context service is unavailable")
	}
	if method != 1 && method != 2 {
		return siteUnitSummaryWorkbookInput{}, errors.New("Summary Environment requires Mean (1) or Interquartile (2)")
	}
	if err := vprocore.ValidateGoogleEarthReviewStrings(contextID); err != nil {
		return siteUnitSummaryWorkbookInput{}, err
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (siteUnitSummaryWorkbookInput, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, hooks, func(owner *vprocore.SqliteContext, tx *sql.Tx) (siteUnitSummaryWorkbookInput, error) {
			return readSiteUnitSummaryWorkbookSource(ctx, owner, tx, contextID, method)
		})
	})
}

func readSiteUnitSummaryWorkbookSource(ctx context.Context, owner *vprocore.SqliteContext, tx *sql.Tx,
	contextID string, method int) (siteUnitSummaryWorkbookInput, error) {
	return readSiteUnitSummaryWorkbookSourceWithScope(ctx, owner, tx, contextID, method, 1)
}
