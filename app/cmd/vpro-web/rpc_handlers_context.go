package main

import (
	"strings"

	"github.com/boostao/vpro/app/internal/classification"
	"github.com/boostao/vpro/app/internal/envreport"
	"github.com/boostao/vpro/app/internal/interchange"
	"github.com/boostao/vpro/app/internal/plotentry"
	"github.com/boostao/vpro/app/internal/projectops"
	"github.com/boostao/vpro/app/internal/sivi"
	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/spatial"
	"github.com/boostao/vpro/app/internal/validation"
	"github.com/boostao/vpro/app/internal/vegreport"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func (r *RPCRouter) registerContextHandlers() {
	const svc = "ContextService"

	r.register(svc, "GetState", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		snap := c.server.currentSnapshot()
		if snap == nil || len(snap.Catalog.Datasets) == 0 {
			return nil, errServiceUnavailable("snapshot catalog is unavailable", 5)
		}
		sel, ok := c.session.Selection()
		var ds vprocore.SnapshotDataset
		if ok {
			if found, exists := snap.FindDataset(sel.DatasetID, ""); exists {
				ds = found
			} else {
				ok = false
			}
		}
		if !ok {
			sel = snap.DefaultSelection()
			ds, _ = snap.FindDataset(sel.DatasetID, "")
			c.session.SetSelection(sel)
		}
		if !datasetHasCompatibleSU(ds, sel.SU) {
			sel.SU = "None"
		}
		if !datasetHasCompatibleHierarchy(ds, sel.Hierarchy) {
			sel.Hierarchy = ds.DefaultHierarchy
		}
		return buildWebProjectState(snap, ds, sel.SU, sel.Hierarchy), nil
	})

	r.register(svc, "SwitchContext", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		_, err := decodeArg[string](c, 0) // expectedID (stateless in web mode)
		if err != nil {
			return nil, err
		}
		requested, err := decodeArg[vprocore.ContextSelection](c, 1)
		if err != nil {
			return nil, err
		}
		snap := c.server.currentSnapshot()
		if snap == nil || len(snap.Catalog.Datasets) == 0 {
			return nil, errServiceUnavailable("snapshot catalog is unavailable", 5)
		}

		// Security: reject arbitrary host filesystem paths outside the verified snapshot.
		if err := c.guardSnapshotDBPath(requested.ProjectPath, "projectPath"); err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(requested.SUPath, "suPath"); err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(requested.HierarchyPath, "hierarchyPath"); err != nil {
			return nil, err
		}

		projectKey := strings.TrimSpace(requested.Project)
		if projectKey == "" {
			projectKey = snap.DefaultSelection().DatasetID
		}
		ds, ok := snap.FindDataset(projectKey, requested.ProjectPath)
		if !ok {
			return nil, errBadRequest("dataset/project %q is not available in active snapshot", requested.Project)
		}

		su := strings.TrimSpace(requested.SU)
		if su == "" {
			su = "None"
		}
		if !datasetHasCompatibleSU(ds, su) {
			return nil, errBadRequest("SU %q is not available in dataset %q", su, ds.ID)
		}

		hier := strings.TrimSpace(requested.Hierarchy)
		if hier == "" {
			hier = "None"
		}
		if !datasetHasCompatibleHierarchy(ds, hier) {
			return nil, errBadRequest("hierarchy %q is not available in dataset %q", hier, ds.ID)
		}

		sel := vprocore.SelectionKey{
			DatasetID: ds.ID,
			SU:        su,
			Hierarchy: hier,
		}
		// Verify slot acquisition succeeds cleanly before returning the stateless context token.
		lease, err := c.server.pool.Acquire(c.ctx, sel, c.session.Prefs)
		if err != nil {
			return nil, err
		}
		lease.Release()

		c.session.SetSelection(sel)
		return buildWebProjectState(snap, ds, su, hier), nil
	})

	r.register(svc, "ListPlots", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		offset, err := decodeArg[int](c, 0)
		if err != nil {
			return nil, err
		}
		limit, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.Projects.ListPlots(c.ctx, offset, limit)
	})

	r.register(svc, "GetHierarchyNodes", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.Projects.GetHierarchyNodes(c.ctx)
	})

	r.register(svc, "CanEditMasterBEC", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		lease.Release()
		// Web server is strictly read-only.
		return false, nil
	})

	r.register(svc, "GetHeaderCapabilities", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.GetHeaderCapabilities(c.ctx, contextID)
	})

	r.register(svc, "GetChildCapabilities", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		kind, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.GetChildCapabilities(c.ctx, contextID, kind)
	})

	r.register(svc, "GetPlot", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.GetPlot(c.ctx, contextID, plot)
	})

	r.register(svc, "GetPlotBundle", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		includeCaps, err := decodeArg[bool](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.GetPlotBundle(c.ctx, contextID, plot, includeCaps)
	})

	r.register(svc, "ListVegRecords", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListVegRecords(c.ctx, contextID, plot)
	})

	r.register(svc, "ListHumusRecords", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListHumusRecords(c.ctx, contextID, plot)
	})

	r.register(svc, "ListMineralRecords", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListMineralRecords(c.ctx, contextID, plot)
	})

	r.register(svc, "ListOtherRecords", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListOtherRecords(c.ctx, contextID, plot)
	})

	r.register(svc, "ListVegetationSpecies", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		form, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListVegetationSpecies(c.ctx, contextID, form)
	})

	r.register(svc, "ListVegetationSpeciesAliases", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lookup, err := decodeArg[vprocore.VegetationSpeciesLookup](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListVegetationSpeciesAliases(c.ctx, contextID, lookup)
	})

	r.register(svc, "ListVegetationSpeciesUsers", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lookup, err := decodeArg[vprocore.VegetationSpeciesLookup](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListVegetationSpeciesUsers(c.ctx, contextID, lookup)
	})

	r.register(svc, "GetVegetationReadAvailability", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.GetVegetationReadAvailability(c.ctx, contextID, plot)
	})

	r.register(svc, "LookupScopedPlot", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vprocore.ScopedPlotLookup](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.LookupScopedPlot(c.ctx, contextID, req)
	})

	r.register(svc, "ReviewProjectMetadata", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ReviewProjectMetadata(c.ctx, contextID, plot)
	})

	// Security guard: reject any client-supplied external filesystem path.
	r.register(svc, "ListPlotProfileSources", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		rawPath, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(rawPath) != "" {
			return nil, errForbidden("external filesystem path argument is not permitted for ListPlotProfileSources in web read-only mode")
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ListPlotProfileSources(c.ctx, contextID, "")
	})

	r.register(svc, "ReadPlotLocations", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lease.Context.ReadPlotLocations(c.ctx, contextID)
	})

	r.register(svc, "RequireSelectedListReportScope", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			return carrier.RequireSelectedListReportScope(contextID)
		})
		if err != nil {
			return nil, err
		}
		return voidResult, nil
	})

	// ContextService Layer-2 delegates

	r.register(svc, "DeriveProjectMetadataFromPlots", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		projectID, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return projectops.DeriveProjectMetadataFromPlots(lease.Context, c.ctx, contextID, projectID)
	})

	r.register(svc, "GetLongEnvironmentOptions", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return envreport.GetLongEnvironmentOptions(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "GetLongVegetationOptions", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out vegreport.LongVegetationOptions
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.GetLongVegetationOptions(carrier, c.ctx, contextID)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "GetPlotLocationReview", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return spatial.GetPlotLocationReview(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "GetProjectTableCSVReview", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		table, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return interchange.GetProjectTableCSVReview(lease.Context, c.ctx, contextID, table)
	})

	r.register(svc, "GetSIVIParentActionOriginal", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return sivi.GetSIVIParentActionOriginal(lease.Context, c.ctx, contextID, plot)
	})

	r.register(svc, "GetSIVIParentDirectOriginal", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return sourceform.GetSIVIParentDirectOriginal(lease.Context, c.ctx, contextID, plot)
	})

	r.register(svc, "GetSIVIParentJoinReview", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return sivi.GetSIVIParentJoinReview(lease.Context, c.ctx, contextID, plot)
	})

	r.register(svc, "GetSIVIParentOriginal", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return sivi.GetSIVIParentOriginal(lease.Context, c.ctx, contextID, plot)
	})

	r.register(svc, "GetSIVIProjectAssignmentOriginal", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return sourceform.GetSIVIProjectAssignmentOriginal(lease.Context, c.ctx, contextID, plot)
	})

	r.register(svc, "GetSIVIProjectIDChoices", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return sivi.GetSIVIProjectIDChoices(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "GetSIVIVegetation", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plot, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		extended, err := decodeArg[bool](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return sivi.GetSIVIVegetation(lease.Context, c.ctx, contextID, plot, extended)
	})

	r.register(svc, "GetSiteUnitSummaryOptions", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return envreport.GetSiteUnitSummaryOptions(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ListProjectMetadataFields", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ListProjectMetadataFields(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ListProjectMetadataPresets", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		return projectops.ListProjectMetadataPresets(), nil
	})

	r.register(svc, "ListProjectPlotProfileChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ListProjectPlotProfileChoices(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ListSoilSuggestions", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return plotentry.ListSoilSuggestions(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ListVegetationAttributeSuggestions", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return plotentry.ListVegetationAttributeSuggestions(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "PreviewLongEnvironment", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[envreport.LongEnvironmentRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return envreport.PreviewLongEnvironment(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "PreviewLongVegetation", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out vegreport.LongVegetationPreview
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.PreviewLongVegetation(carrier, c.ctx, contextID)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "PreviewOptimizeVeg", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		opts, err := decodeArg[projectops.OptimizeVegOptions](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return projectops.PreviewOptimizeVeg(lease.Context, c.ctx, contextID, opts)
	})

	r.register(svc, "PreviewSiteUnitSummary", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[envreport.SiteUnitSummaryRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return envreport.PreviewSiteUnitSummary(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "PreviewSiteUnitSummaryLifeforms", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[envreport.SiteUnitSummaryRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return envreport.PreviewSiteUnitSummaryLifeforms(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "PreviewSiteUnitSummarySpecies", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[envreport.SiteUnitSpeciesListRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return envreport.PreviewSiteUnitSummarySpecies(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "ResolveProjectPlotProfileNavigation", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[classification.ProjectPlotProfileFilterRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ResolveProjectPlotProfileNavigation(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "ReviewEnvironmentSiteUnits", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewEnvironmentSiteUnits(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ReviewProjectPlotProfile", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewProjectPlotProfile(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ReviewProjectPlotProfileLump", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewProjectPlotProfileLump(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ReviewProjectPlotProfileSU", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[classification.ProjectPlotProfileFilterRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewProjectPlotProfileSU(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "ReviewProjectPlotProfileSUInProject", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[classification.ProjectPlotProfileFilterRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewProjectPlotProfileSUInProject(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "ReviewSiteUnitEnvironment", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewSiteUnitEnvironment(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "RunComplianceValidation", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		opts, err := decodeArg[validation.ComplianceOptions](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return validation.RunComplianceValidation(lease.Context, c.ctx, contextID, opts)
	})

	r.register(svc, "RunProjectPlotProfile", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[classification.ProjectPlotProfileRunRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.RunProjectPlotProfile(lease.Context, c.ctx, contextID, req)
	})
}
