package vegreport

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/boostao/vpro/app/internal/reports/reportcore"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func PreviewSiteUnitExclusions(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	request SiteUnitExclusionPreviewRequest,
) (*SiteUnitExclusionPreview, error) {
	if ctx == nil {
		return nil, errors.New("SiteUnit exclusion preview requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("vegetation report context service is unavailable")
	}
	rules, err := NormalizeExclusionRules(request.Rules, request.UseDefaultPresets)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*SiteUnitExclusionPreview, error) {
		owner := plots.Projects.Sqlite
		if owner.Selection.SU == "" || owner.Selection.SU == "None" {
			return nil, errors.New("an active Site Unit (SU) table must be selected")
		}
		return vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (*SiteUnitExclusionPreview, error) {
			if err := vprocore.ProfileOwnedFiles(owner); err != nil {
				return nil, err
			}
			suTable, err := vprocore.ReadSQLiteStorageRows(ctx, tx, "su", owner.Selection.SU+"_SU", "", nil, "")
			if err != nil {
				return nil, err
			}
			filteredSU, summary, err := FilterSUTableByExclusions(suTable, rules)
			if err != nil {
				return nil, err
			}

			out := &SiteUnitExclusionPreview{
				ContextID:  contextID,
				Project:    owner.Selection.Project,
				SU:         owner.Selection.SU,
				Hierarchy:  owner.Selection.Hierarchy,
				Exclusions: summary,
			}

			if request.UseHierarchyBreakpoints {
				if owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None" {
					return nil, errors.New("an active Hierarchy table must be selected when UseHierarchyBreakpoints is enabled")
				}
				nodes, hErr := loadHierarchyNodesFromTx(ctx, tx, owner.Selection.Hierarchy)
				if hErr != nil {
					return nil, hErr
				}
				_, bpRes, bErr := resolveHierarchyBreakpointsOnSU(filteredSU, nodes, request.BreakpointOptions)
				if bErr != nil {
					return nil, bErr
				}
				bpRes.ContextID = contextID
				bpRes.Project = owner.Selection.Project
				bpRes.SU = owner.Selection.SU
				bpRes.Hierarchy = owner.Selection.Hierarchy
				out.Breakpoints = &bpRes
			}

			if err := vprocore.ProfileOwnedFiles(owner); err != nil {
				return nil, err
			}
			return out, nil
		})
	})
}

func PreviewSummaryVegetationWithExclusions(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	request SummaryVegetationExclusionRequest,
) (*SummaryVegetationExclusionPreview, error) {
	if ctx == nil {
		return nil, errors.New("Summary Vegetation requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil || contexts.Projects == nil || contexts.Projects.Sqlite == nil || contexts.Plots == nil {
		return nil, errors.New("Summary Vegetation context service is unavailable")
	}
	if err := vprocore.ValidateGoogleEarthReviewStrings(contextID); err != nil {
		return nil, err
	}

	average := request.Average
	if average == 0 {
		average = 1
	}
	display := request.Display
	if display == 0 {
		display = 6
	}
	showClass := request.ShowClass
	groupAndOrder := request.GroupAndOrder
	if groupAndOrder == 0 {
		groupAndOrder = 11
	}
	if groupAndOrder == 11 {
		if err := validateSummaryVegetationDisplayOptions(ctx, average, display, showClass); err != nil {
			return nil, err
		}
	} else {
		if err := validateSummaryVegetationGroupedOptions(ctx, average, groupAndOrder, display, showClass); err != nil {
			return nil, err
		}
	}

	rules, err := NormalizeExclusionRules(request.Rules, request.UseDefaultPresets)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*SummaryVegetationExclusionPreview, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*SummaryVegetationExclusionPreview, error) {
			if owner.Selection.SU == "" || owner.Selection.SU == "None" {
				return nil, errors.New("Summary Vegetation requires a selected Site Unit (SU) table")
			}

			tables := make([]vprocore.ProjectMetadataTable, 5)
			for i, source := range []struct{ role, table string }{
				{"project", owner.Selection.Project + "_Veg"},
				{"su", owner.Selection.SU + "_SU"},
				{"VLists", "USysAllSpecs"},
				{"VUser", "USysUserSpp"},
				{"VPro64", "LayerCode"},
			} {
				var count int
				if err := tx.QueryRowContext(ctx,
					`SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(source.role)+`.sqlite_master WHERE type='table' AND name COLLATE BINARY=?`,
					source.table,
				).Scan(&count); err != nil {
					return nil, err
				}
				if count != 1 {
					return nil, fmt.Errorf("Summary Vegetation requires original physical table %s.%s", source.role, source.table)
				}
				tbl, tErr := vprocore.ReadSQLiteStorageRows(ctx, tx, source.role, source.table, "", nil, "")
				if tErr != nil {
					return nil, tErr
				}
				tables[i] = tbl
			}

			effectiveSU, exclusionSummary, err := FilterSUTableByExclusions(tables[1], rules)
			if err != nil {
				return nil, err
			}

			var bpResolution *HierarchyBreakpointResolution
			if request.UseHierarchyBreakpoints {
				if owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None" {
					return nil, errors.New("an active Hierarchy table must be selected when UseHierarchyBreakpoints is enabled")
				}
				nodes, hErr := loadHierarchyNodesFromTx(ctx, tx, owner.Selection.Hierarchy)
				if hErr != nil {
					return nil, hErr
				}
				rolledSU, bpRes, bErr := resolveHierarchyBreakpointsOnSU(effectiveSU, nodes, request.BreakpointOptions)
				if bErr != nil {
					return nil, bErr
				}
				bpRes.ContextID = contextID
				bpRes.Project = owner.Selection.Project
				bpRes.SU = owner.Selection.SU
				bpRes.Hierarchy = owner.Selection.Hierarchy
				effectiveSU = rolledSU
				bpResolution = &bpRes
			}

			var references *summaryVegetationReferencePlan
			refOpts := SummaryVegetationReferenceOptions{}
			if request.References != nil {
				refOpts = *request.References
			}
			var hasDesc int
			_ = tx.QueryRowContext(ctx,
				`SELECT COUNT(*) FROM "VLists".sqlite_master WHERE type='table' AND name COLLATE BINARY='USysSppAttributeDescription'`,
			).Scan(&hasDesc)
			_, hasIsAttrErr := vprocore.SiteUnitTransferColumns(tables[2], "IsAttribute")
			if request.References != nil || (hasDesc == 1 && hasIsAttrErr == nil && summaryVegetationReferenceGroupingAvailable(groupAndOrder, refOpts.ShowCommon || refOpts.UseGuideNames)) {
				descTable, dErr := vprocore.ReadSQLiteStorageRows(ctx, tx, "VLists", "USysSppAttributeDescription", "", nil, "")
				if dErr != nil {
					return nil, dErr
				}
				plan, pErr := prepareSummaryVegetationReferences(ctx, tables[2], tables[3], descTable, refOpts)
				if pErr != nil {
					return nil, pErr
				}
				references = &plan
			}

			var report summaryVegetationLayerReport
			var grouped summaryVegetationGroupedReport
			if groupAndOrder == 11 {
				report, err = prepareSummaryVegetationLayerReferences(
					ctx, owner.Selection.Project, owner.Selection.SU,
					tables[0], effectiveSU, tables[2], tables[3], tables[4],
					average, display, showClass, references,
				)
			} else {
				grouped, err = prepareSummaryVegetationGroupedReferences(
					ctx, owner.Selection.Project, owner.Selection.SU,
					tables[0], effectiveSU, tables[2], tables[3], tables[4],
					average, groupAndOrder, display, showClass, references,
				)
				report = grouped.Report
			}
			if err != nil {
				return nil, err
			}

			sourceTag := "literal-normal-su-layer"
			if len(exclusionSummary.ExcludedUnits) > 0 && bpResolution != nil {
				sourceTag = "literal-filtered-su-hierarchy-breakpoints"
			} else if bpResolution != nil {
				sourceTag = "literal-normal-su-hierarchy-breakpoints"
			} else if len(exclusionSummary.ExcludedUnits) > 0 {
				sourceTag = "literal-filtered-su-layer"
			}

			preview := SummaryVegetationPreview{
				ContextID:   contextID,
				Project:     owner.Selection.Project,
				ProjectPath: owner.Selection.ProjectPath,
				SU:          owner.Selection.SU,
				SUPath:      owner.Selection.SUPath,
				Average:     average,
				Display:     display,
				ShowClass:   showClass,
				Source:      sourceTag,
				Ordering:    "literal-null-first-layer-species",
				Memberships: []reportcore.VegetationReportMembership{},
				Units:       []SummaryVegetationUnit{},
				Columns:     append([]string{}, report.Columns...),
				Rows:        []SummaryVegetationRow{},
			}
			if references != nil {
				preview.References = &references.Review
			}
			if groupAndOrder != 11 {
				preview.GroupAndOrder = groupAndOrder
				preview.GroupField = &SummaryVegetationField{grouped.GroupField.Name, grouped.GroupField.DAOType, grouped.GroupField.Size}
				preview.OrderField = &SummaryVegetationField{grouped.OrderField.Name, grouped.OrderField.DAOType, grouped.OrderField.Size}
				preview.Ordering = "literal-null-first-group-species"
			}

			uc, err := vprocore.SiteUnitTransferColumns(effectiveSU, "PlotNumber", "SiteUnit")
			if err != nil {
				return nil, err
			}
			for _, row := range effectiveSU.Rows {
				preview.Memberships = append(preview.Memberships, reportcore.VegetationReportMembership{
					RowID:      row.RowID,
					PlotNumber: vprocore.CloneSiteUnitCell(row.Cells[uc["PlotNumber"]]),
					SiteUnit:   vprocore.CloneSiteUnitCell(row.Cells[uc["SiteUnit"]]),
				})
			}
			for _, u := range report.Units {
				preview.Units = append(preview.Units, SummaryVegetationUnit{
					Code:          u.Code,
					NumPlots:      u.NumPlots,
					MembershipIDs: append([]string{}, u.MembershipIDs...),
					RawVegRowIDs:  append([]string{}, u.RawVegRowIDs...),
				})
			}
			for _, row := range report.Rows {
				transport := SummaryVegetationRow{
					Layer:     vprocore.CloneSiteUnitCell(row.Layer),
					Species:   vprocore.CloneSiteUnitCell(row.Species),
					Order:     vprocore.CloneSiteUnitCell(row.Order),
					Covers:    make([]vprocore.ProjectMetadataCell, 0, len(row.Covers)),
					Witnesses: make([]SummaryVegetationWitness, 0, len(row.Witnesses)),
				}
				if row.CommonName != nil {
					v := vprocore.CloneSiteUnitCell(*row.CommonName)
					transport.CommonName = &v
				}
				if row.RawSpecies != nil {
					v := vprocore.CloneSiteUnitCell(*row.RawSpecies)
					transport.RawSpecies = &v
				}
				for _, c := range row.Covers {
					transport.Covers = append(transport.Covers, vprocore.CloneSiteUnitCell(c))
				}
				for _, w := range row.Witnesses {
					origins := make([]SummaryVegetationReferenceOrigin, 0, len(w.ReferenceOrigins))
					for _, o := range w.ReferenceOrigins {
						origins = append(origins, SummaryVegetationReferenceOrigin{Table: o.Table, RowID: o.RowID})
					}
					transport.Witnesses = append(transport.Witnesses, SummaryVegetationWitness{
						StageRowID:        w.StageRowID,
						ConversionLayerID: w.ConversionLayerID,
						MembershipID:      w.MembershipID,
						Unit:              w.Unit,
						LayerMapID:        w.LayerMapID,
						ReferenceOrigins:  origins,
						RawVegRowIDs:      append([]string{}, w.RawVegRowIDs...),
						Cover:             vprocore.CloneSiteUnitCell(w.Cover),
					})
				}
				preview.Rows = append(preview.Rows, transport)
			}

			return &SummaryVegetationExclusionPreview{
				Preview:     preview,
				Exclusions:  exclusionSummary,
				Breakpoints: bpResolution,
			}, nil
		})
	})
}

func PreviewLongVegetationWithExclusions(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	request LongVegetationExclusionRequest,
) (*LongVegetationExclusionPreview, error) {
	if ctx == nil {
		return nil, errors.New("Long Vegetation requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil || contexts.Projects == nil || contexts.Projects.Sqlite == nil || contexts.Plots == nil {
		return nil, errors.New("Long Vegetation context service is unavailable")
	}
	rules, err := NormalizeExclusionRules(request.Rules, request.UseDefaultPresets)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*LongVegetationExclusionPreview, error) {
		return vprocore.WithOwnedPreferenceSnapshot(ctx, plots, vprocore.PublicationReadSnapshotHooks{}, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*LongVegetationExclusionPreview, error) {
			if owner.Selection.SU == "" || owner.Selection.SU == "None" {
				return nil, errors.New("Long Vegetation requires an explicitly selected SU, not an all-project fallback")
			}

			values, err := plots.Projects.Preferences.Snapshot()
			if err != nil {
				return nil, err
			}
			options, err := DecodeOwnedLongVegetationOptions(contexts, ctx, plots, tx, values)
			if err != nil {
				return nil, err
			}
			if err := CheckLongVegetationGrouping(contexts, options); err != nil {
				return nil, err
			}

			sources := []struct{ role, table string }{
				{"project", owner.Selection.Project + "_Veg"},
				{"su", owner.Selection.SU + "_SU"},
				{"VLists", "USysAllSpecs"},
				{"VPro64", "LayerCode"},
				{"VLists", "MasterSiteUnitList"},
			}
			if options.Quality != nil || options.NoneUnits || options.SelectedUnitFields != nil {
				sources = append(sources, struct{ role, table string }{"project", owner.Selection.Project + "_Env"})
			}
			if options.Quality != nil || options.SelectedUnitFields != nil {
				sources = append(sources, struct{ role, table string }{"project", owner.Selection.Project + "_Admin"})
			}
			if options.Quality != nil {
				sources = append(sources, struct{ role, table string }{"VLists", "USysTableOfLists"})
			}
			personalIndex := -1
			if options.LifeformGrouping {
				personalIndex = len(sources)
				sources = append(sources, struct{ role, table string }{"VUser", "USysUserSpp"})
			}

			tables := make([]vprocore.ProjectMetadataTable, len(sources))
			for i, source := range sources {
				var count int
				if err := tx.QueryRowContext(ctx,
					`SELECT COUNT(*) FROM `+vprocore.QuoteHeaderIdentifier(source.role)+`.sqlite_master WHERE type='table' AND name COLLATE BINARY=?`,
					source.table,
				).Scan(&count); err != nil {
					return nil, err
				}
				if count != 1 {
					return nil, fmt.Errorf("Long Vegetation requires original physical table %s.%s", source.role, source.table)
				}
				tbl, tErr := vprocore.ReadSQLiteStorageRows(ctx, tx, source.role, source.table, "", nil, "")
				if tErr != nil {
					return nil, tErr
				}
				tables[i] = tbl
			}

			effectiveSU, exclusionSummary, err := FilterSUTableByExclusions(tables[1], rules)
			if err != nil {
				return nil, err
			}

			var bpResolution *HierarchyBreakpointResolution
			if request.UseHierarchyBreakpoints {
				if owner.Selection.Hierarchy == "" || owner.Selection.Hierarchy == "None" {
					return nil, errors.New("an active Hierarchy table must be selected when UseHierarchyBreakpoints is enabled")
				}
				nodes, hErr := loadHierarchyNodesFromTx(ctx, tx, owner.Selection.Hierarchy)
				if hErr != nil {
					return nil, hErr
				}
				rolledSU, bpRes, bErr := resolveHierarchyBreakpointsOnSU(effectiveSU, nodes, request.BreakpointOptions)
				if bErr != nil {
					return nil, bErr
				}
				bpRes.ContextID = contextID
				bpRes.Project = owner.Selection.Project
				bpRes.SU = owner.Selection.SU
				bpRes.Hierarchy = owner.Selection.Hierarchy
				effectiveSU = rolledSU
				bpResolution = &bpRes
			}

			var prepared VegetationReportPreparation
			var quality vegetationQualitySelection
			var noneUnits []vegetationNoneUnitOccurrence
			var selectedUnits []vegetationSelectedUnitOccurrence

			if options.SelectedUnitFields != nil {
				var qualified *vegetationQualitySelection
				if options.Quality != nil {
					quality, err = planLongVegetationQuality(ctx, effectiveSU, tables[5], tables[6], tables[7], *options.Quality)
					if err != nil {
						return nil, err
					}
					qualified = &quality
				}
				prepared, selectedUnits, err = prepareLongVegetationSelectedUnits(ctx, owner.Selection.Project, owner.Selection.SU,
					tables[0], effectiveSU, tables[3], tables[5], tables[6], options.SelectedUnitFields, qualified)
				if err == nil && len(selectedUnits) == 0 {
					err = errors.New("Long Vegetation selected report units have no derived memberships after SiteUnit exclusions")
				}
			} else if options.NoneUnits {
				var qualified *vegetationQualitySelection
				if options.Quality != nil {
					quality, err = planLongVegetationQuality(ctx, effectiveSU, tables[5], tables[6], tables[7], *options.Quality)
					if err != nil {
						return nil, err
					}
					qualified = &quality
				}
				prepared, noneUnits, err = prepareLongVegetationNoneUnits(ctx, owner.Selection.Project, owner.Selection.SU,
					tables[0], effectiveSU, tables[3], tables[5], qualified)
				if err == nil && len(noneUnits) == 0 {
					err = errors.New("Long Vegetation None report units have no joined Env/SU plots after SiteUnit exclusions")
				}
			} else if options.Quality == nil {
				prepared, err = prepareLongVegetation(ctx, owner.Selection.Project, owner.Selection.SU, tables[0], effectiveSU, tables[3])
			} else {
				prepared, quality, err = prepareQualityLongVegetation(ctx, owner.Selection.Project, owner.Selection.SU,
					tables[0], effectiveSU, tables[3], tables[5], tables[6], tables[7], *options.Quality)
			}
			if err != nil {
				return nil, err
			}
			if options.Quality != nil && len(quality.Occurrences) == 0 {
				return nil, errors.New("no plots remain after applying plot quality standards and SiteUnit exclusions")
			}

			var personal vprocore.ProjectMetadataTable
			if personalIndex >= 0 {
				personal = tables[personalIndex]
			}
			report, err := planLongVegetationPreparedSource(ctx, prepared, tables[2], personal, tables[3], options)
			if err != nil {
				return nil, err
			}
			if options.Quality != nil {
				report.Quality = &quality
				if options.NoneUnits || options.SelectedUnitFields != nil {
					if err := addLongVegetationQualityMultiplicity(ctx, &report, quality); err != nil {
						return nil, err
					}
				}
			}
			report.NoneUnits = noneUnits
			report.SelectedUnits = selectedUnits
			if err := addLongVegetationUnitNames(ctx, &report, tables[4]); err != nil {
				return nil, err
			}

			transport, err := longVegetationTransport(ctx, report)
			if err != nil {
				return nil, err
			}
			lvPreview := LongVegetationPreview{
				ContextID:   contextID,
				ProjectPath: owner.Selection.ProjectPath,
				SUPath:      owner.Selection.SUPath,
				Settings:    vegetationSettings(options),
				Report:      transport,
			}

			return &LongVegetationExclusionPreview{
				Preview:     lvPreview,
				Exclusions:  exclusionSummary,
				Breakpoints: bpResolution,
			}, nil
		})
	})
}
