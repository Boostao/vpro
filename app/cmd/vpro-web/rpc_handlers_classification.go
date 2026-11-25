package main

import (
	"context"
	"errors"
	"os"
	"strings"

	"github.com/boostao/vpro/app/internal/classification"
	"github.com/boostao/vpro/app/internal/diagnostics"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func (r *RPCRouter) registerClassificationHandlers() {
	const svc = "ClassificationService"

	newLeaseWorkingUnits := func(c *rpcCall, lease *vprocore.ReadOnlyLease) (*vprocore.WorkingUnitService, error) {
		if c.server.refs == nil {
			return nil, errors.New("working unit catalogue is unavailable")
		}
		p := lease.Context.Projects
		proxy := &vprocore.ProjectService{
			Root:         c.server.refs.refDir,
			Active:       p.Active,
			ActiveSU:     p.ActiveSU,
			Preferences:  p.Preferences,
			Sqlite:       p.Sqlite,
			SupportPaths: p.SupportPaths,
			ContextID:    p.ContextID,
		}
		return vprocore.NewWorkingUnitService(proxy, c.server.refs.configDir)
	}

	// BEC Catalogue

	r.register(svc, "GetBECCatalogueStatus", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.bec == nil {
			return nil, errors.New("BEC catalogue service is unavailable")
		}
		return c.server.refs.bec.GetBECCatalogueStatus(c.ctx)
	})

	r.register(svc, "ListBECZones", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.bec == nil {
			return nil, errors.New("BEC catalogue service is unavailable")
		}
		return c.server.refs.bec.ListBECZones(c.ctx)
	})

	r.register(svc, "ListBECSubZones", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		zone, err := decodeArg[*string](c, 0)
		if err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.bec == nil {
			return nil, errors.New("BEC catalogue service is unavailable")
		}
		return c.server.refs.bec.ListBECSubZones(c.ctx, zone)
	})

	r.register(svc, "ListBECSiteSeries", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		zone, err := decodeArg[*string](c, 0)
		if err != nil {
			return nil, err
		}
		subZone, err := decodeArg[*string](c, 1)
		if err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.bec == nil {
			return nil, errors.New("BEC catalogue service is unavailable")
		}
		return c.server.refs.bec.ListBECSiteSeries(c.ctx, zone, subZone)
	})

	r.register(svc, "SearchBECSiteSeries", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(4); err != nil {
			return nil, err
		}
		zone, err := decodeArg[*string](c, 0)
		if err != nil {
			return nil, err
		}
		subZone, err := decodeArg[*string](c, 1)
		if err != nil {
			return nil, err
		}
		query, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		limit, err := decodeArg[int](c, 3)
		if err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.bec == nil {
			return nil, errors.New("BEC catalogue service is unavailable")
		}
		return c.server.refs.bec.SearchBECSiteSeries(c.ctx, zone, subZone, query, limit)
	})

	// Working Units (mode stored per-session in memory DesktopConfig)

	r.register(svc, "GetWorkingUnitMode", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		wu, err := newLeaseWorkingUnits(c, lease)
		if err != nil {
			return nil, err
		}
		defer wu.Close()
		return wu.GetWorkingUnitModeContext(c.ctx)
	})

	r.register(svc, "SetWorkingUnitMode", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		mode, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		wu, err := newLeaseWorkingUnits(c, lease)
		if err != nil {
			return nil, err
		}
		defer wu.Close()
		return wu.SetWorkingUnitModeContext(c.ctx, mode)
	})

	r.register(svc, "GetWorkingUnitChoices", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		mode, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		wu, err := newLeaseWorkingUnits(c, lease)
		if err != nil {
			return nil, err
		}
		defer wu.Close()
		return wu.GetWorkingUnitChoices(c.ctx, mode)
	})

	r.register(svc, "GetMasterWorkingUnitChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.masterWU == nil {
			return nil, errors.New("working unit service is unavailable")
		}
		return c.server.refs.masterWU.GetMasterWorkingUnitChoices(c.ctx)
	})

	// External SU / Two-Page Profiling / Species Presence / Hierarchy

	r.register(svc, "GetExternalSUEnvironmentReview", "rpc", true, func(c *rpcCall) (any, error) {
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
		return classification.NewExternalSUEnvironmentService(lease.Context).GetReview(c.ctx, contextID)
	})

	r.register(svc, "GetTwoPageProfilingReview", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := classification.NewTwoPageProfilingService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID, plot, offset, limit)
	})

	r.register(svc, "PreviewSpeciesPresence", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		requestJSON, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := classification.NewProjectProfileSpeciesPresenceService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.Preview(c.ctx, contextID, requestJSON)
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

	r.register(svc, "ListProjectPlotProfileLumpTables", "rpc", true, func(c *rpcCall) (any, error) {
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
		return classification.ListProjectPlotProfileLumpTables(lease.Context, c.ctx, contextID)
	})

	r.register(svc, "ReviewProjectPlotProfileLumpTable", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		location, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewProjectPlotProfileLumpTable(lease.Context, c.ctx, contextID, location)
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

	r.register(svc, "ReviewProjectPlotProfileSU", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		filter, err := decodeArg[classification.ProjectPlotProfileFilterRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewProjectPlotProfileSU(lease.Context, c.ctx, contextID, filter)
	})

	r.register(svc, "ReviewProjectPlotProfileSUInProject", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		filter, err := decodeArg[classification.ProjectPlotProfileFilterRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.ReviewProjectPlotProfileSUInProject(lease.Context, c.ctx, contextID, filter)
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

	r.register(svc, "GetSUPlotTree", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		filterText, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.GetSUPlotTree(c.ctx, lease.Context, contextID, filterText)
	})

	r.register(svc, "GetPlotInspectorSummary", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		plotNumber, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return classification.GetPlotInspectorSummary(c.ctx, lease.Context, contextID, plotNumber)
	})

	r.register(svc, "SearchBECUnitPicker", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[classification.BECUnitPickerRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var bec *referencesServiceAlias
		if c.server.refs != nil {
			bec = c.server.refs.bec
		}
		return classification.SearchBECUnitPicker(c.ctx, lease.Context, bec, contextID, req)
	})

	r.register(svc, "GetHierarchyExplorer", "rpc", true, func(c *rpcCall) (any, error) {
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
		return classification.GetHierarchyExplorer(c.ctx, lease.Context, contextID)
	})

	// BEC Diagnostics & Synthesis

	r.register(svc, "ListSynthesisLumpTables", "rpc", true, func(c *rpcCall) (any, error) {
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
		return diagnostics.ListSynthesisLumpTables(c.ctx, lease.Context, contextID)
	})

	r.register(svc, "ComputeSynthesisSnapshot", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		opts, err := decodeArg[diagnostics.SynthesisOptions](c, 1)
		if err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(opts.LumpDBPath, "options.lumpDbPath"); err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return diagnostics.ComputeSynthesisSnapshot(c.ctx, lease.Context, contextID, opts)
	})

	r.register(svc, "ExportDiagnosticWorkbook", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[diagnostics.ExportDiagnosticWorkbookRequest](c, 1)
		if err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(req.Options.LumpDBPath, "options.lumpDbPath"); err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-diagnostics.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.OutputPath = filePath // Strictly ignore any client-supplied outputPath.

			outcome, err := diagnostics.ExportDiagnosticWorkbook(ctx, lease.Context, contextID, req)
			if err != nil {
				cleanup()
				return nil, err
			}
			_, dlURL, safeName, err := c.server.downloads.Register(outcome.Path, dirPath, filename)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome.Path = safeName
			return &downloadResult{
				Outcome:     outcome,
				DownloadURL: dlURL,
				Filename:    safeName,
			}, nil
		})
	})

	r.register(svc, "ListUserSiteUnitList", "rpc", true, func(c *rpcCall) (any, error) {
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
		return classification.ListUserSiteUnitList(c.ctx, lease.Context, contextID)
	})

	r.register(svc, "ExportUserSiteUnitListCSV", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			csvText, err := classification.ExportUserSiteUnitListCSV(ctx, lease.Context, contextID)
			if err != nil {
				return nil, err
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-user-site-units.csv")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			if err := os.WriteFile(filePath, []byte(csvText), 0o600); err != nil {
				cleanup()
				return nil, err
			}
			_, dlURL, safeName, err := c.server.downloads.Register(filePath, dirPath, filename)
			if err != nil {
				cleanup()
				return nil, err
			}
			return &downloadResult{
				Outcome:     csvText,
				DownloadURL: dlURL,
				Filename:    safeName,
			}, nil
		})
	})
}
