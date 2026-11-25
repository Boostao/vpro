package main

import (
	"github.com/boostao/vpro/app/internal/datasheet"
	"github.com/boostao/vpro/app/internal/lifecycle"
	"github.com/boostao/vpro/app/internal/projectops"
	"github.com/boostao/vpro/app/internal/references"
	"github.com/boostao/vpro/app/internal/validation"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type referencesServiceAlias = references.BECService

func (r *RPCRouter) registerMiscHandlers() {
	// --- DatasheetService (6 RPCs) ---
	{
		const svc = "DatasheetService"

		r.register(svc, "GetEnvironmentTableReview", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(4); err != nil {
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
			offset, err := decodeArg[int](c, 2)
			if err != nil {
				return nil, err
			}
			limit, err := decodeArg[int](c, 3)
			if err != nil {
				return nil, err
			}
			lease, err := c.acquireByContextID(contextID)
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			s, err := datasheet.NewTwoPageEnvironmentTableService(lease.Context)
			if err != nil {
				return nil, err
			}
			return s.GetReview(c.ctx, contextID, plot, offset, limit)
		})

		r.register(svc, "GetVegetationTableReview", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(5); err != nil {
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
			form, err := decodeArg[string](c, 2)
			if err != nil {
				return nil, err
			}
			offset, err := decodeArg[int](c, 3)
			if err != nil {
				return nil, err
			}
			limit, err := decodeArg[int](c, 4)
			if err != nil {
				return nil, err
			}
			lease, err := c.acquireByContextID(contextID)
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			s, err := datasheet.NewTwoPageVegetationTableService(lease.Context)
			if err != nil {
				return nil, err
			}
			return s.GetReview(c.ctx, contextID, plot, form, offset, limit)
		})

		r.register(svc, "ListDatasheetTables", "rpc", true, func(c *rpcCall) (any, error) {
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
			return datasheet.ListDatasheetTables(c.ctx, lease.Context, contextID)
		})

		r.register(svc, "ListDatasheetAllTables", "rpc", true, func(c *rpcCall) (any, error) {
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
			return datasheet.ListDatasheetAllTables(c.ctx, lease.Context, contextID)
		})

		r.register(svc, "GetDatasheetPage", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(2); err != nil {
				return nil, err
			}
			contextID, err := decodeArg[string](c, 0)
			if err != nil {
				return nil, err
			}
			req, err := decodeArg[datasheet.DatasheetPageRequest](c, 1)
			if err != nil {
				return nil, err
			}
			lease, err := c.acquireByContextID(contextID)
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			return datasheet.GetDatasheetPage(c.ctx, lease.Context, contextID, req)
		})

		r.register(svc, "PreviewDatasheetFindReplace", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(2); err != nil {
				return nil, err
			}
			contextID, err := decodeArg[string](c, 0)
			if err != nil {
				return nil, err
			}
			req, err := decodeArg[datasheet.DatasheetFindReplaceRequest](c, 1)
			if err != nil {
				return nil, err
			}
			lease, err := c.acquireByContextID(contextID)
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			return datasheet.PreviewDatasheetFindReplace(c.ctx, lease.Context, contextID, req)
		})
	}

	// --- HelpService (8 RPCs: 7 rpc + 1 prefs) ---
	{
		const svc = "HelpService"

		r.register(svc, "GetLibraryStamps", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(0); err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.GetLibraryStamps(c.ctx)
		})

		r.register(svc, "GetReleaseChannel", "rpc", false, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(0); err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.GetReleaseChannel(c.ctx)
		})

		r.register(svc, "GetAboutInfo", "rpc", false, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(0); err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.GetAboutInfo(c.ctx)
		})

		r.register(svc, "GetHelpBundle", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(0); err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.GetHelpBundle(c.ctx)
		})

		r.register(svc, "LookupHelpTopic", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(1); err != nil {
				return nil, err
			}
			helpID, err := decodeArg[string](c, 0)
			if err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.LookupHelpTopic(c.ctx, helpID)
		})

		r.register(svc, "SearchHelp", "rpc", true, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(1); err != nil {
				return nil, err
			}
			query, err := decodeArg[string](c, 0)
			if err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.SearchHelp(c.ctx, query)
		})

		r.register(svc, "GetWhatsNewStatus", "rpc", false, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(0); err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.GetWhatsNewStatus(c.ctx)
		})

		r.register(svc, "AcknowledgeWhatsNew", "prefs", false, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(1); err != nil {
				return nil, err
			}
			version, err := decodeArg[string](c, 0)
			if err != nil {
				return nil, err
			}
			help, err := c.server.buildHelpServiceForSession(c.session.Prefs, nil)
			if err != nil {
				return nil, err
			}
			return help.AcknowledgeWhatsNew(c.ctx, version)
		})
	}

	// --- LifecycleService (1 RPC) ---
	{
		const svc = "LifecycleService"

		r.register(svc, "GetStartupState", "rpc", false, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(0); err != nil {
				return nil, err
			}
			snap := c.server.currentSnapshot()
			if snap == nil || len(snap.Catalog.Datasets) == 0 {
				return lifecycle.WithBuildMetadata(lifecycle.StartupState{
					Ready:          false,
					Message:        "snapshot catalog is unavailable",
					ReleaseChannel: vprocore.ReleaseChannelStable,
				}), nil
			}
			sel := snap.DefaultSelection()
			ds, _ := snap.FindDataset(sel.DatasetID, "")
			return lifecycle.WithBuildMetadata(lifecycle.StartupState{
				Ready:               true,
				ReleaseChannel:      vprocore.ReleaseChannelStable,
				ConfiguredProject:   ds.Project,
				ProjectPath:         ds.ProjectPath,
				ConfiguredSU:        sel.SU,
				ConfiguredHierarchy: sel.Hierarchy,
			}), nil
		})
	}

	// --- PictureService (3 RPCs) ---
	{
		const svc = "PictureService"

		r.register(svc, "GetPictureOptions", "rpc", false, func(c *rpcCall) (any, error) {
			if err := c.requireArgCount(0); err != nil {
				return nil, err
			}
			lease, _, err := c.acquireSessionLease()
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			picSvc, err := c.server.buildReadOnlyPictureService(lease.Context)
			if err != nil {
				return nil, err
			}
			return picSvc.GetPictureOptions(c.ctx)
		})

		r.register(svc, "GetMetadata", "rpc", true, func(c *rpcCall) (any, error) {
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
			picSvc, err := c.server.buildReadOnlyPictureService(lease.Context)
			if err != nil {
				return nil, err
			}
			return picSvc.GetMetadata(c.ctx, contextID, plot)
		})

		r.register(svc, "GetImage", "rpc", false, func(c *rpcCall) (any, error) {
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
			requestJSON, err := decodeArg[string](c, 2)
			if err != nil {
				return nil, err
			}
			lease, err := c.acquireByContextID(contextID)
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			picSvc, err := c.server.buildReadOnlyPictureService(lease.Context)
			if err != nil {
				return nil, err
			}
			return picSvc.GetImage(c.ctx, contextID, plot, requestJSON)
		})
	}

	// --- ValidationService (2 RPCs) ---
	{
		const svc = "ValidationService"

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
	}
}
