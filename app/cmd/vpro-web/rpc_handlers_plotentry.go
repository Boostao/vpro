package main

import (
	"errors"

	"github.com/boostao/vpro/app/internal/classification"
	"github.com/boostao/vpro/app/internal/lmh25rules"
	"github.com/boostao/vpro/app/internal/plotentry"
	"github.com/boostao/vpro/app/internal/sivi"
	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/twopage"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func (r *RPCRouter) registerPlotEntryHandlers() {
	const svc = "PlotEntryService"

	buildTwoPageEntryReaders := func(refs *webReferenceCatalogs) twopage.TwoPageEntryReferenceReaders {
		var readers twopage.TwoPageEntryReferenceReaders
		if refs == nil {
			return readers
		}
		if refs.siteCodes != nil {
			readers.Shared.Site = refs.siteCodes
		}
		if refs.regionCodes != nil {
			readers.Shared.Region = refs.regionCodes
			readers.Ecosection = refs.regionCodes
		}
		if refs.parentCodes != nil {
			readers.Shared.Parent = refs.parentCodes
		}
		if refs.geologyCodes != nil {
			readers.Shared.Geology = refs.geologyCodes
		}
		if refs.bec != nil {
			readers.Shared.Bec = refs.bec
			readers.Series = refs.bec
		}
		if refs.quality != nil {
			readers.Quality = refs.quality
		}
		if refs.soilCodes != nil {
			readers.Soil = refs.soilCodes
		}
		return readers
	}

	buildSIVISharedReaders := func(refs *webReferenceCatalogs) sourceform.SourceParentSharedReferenceReaders {
		if refs == nil {
			return sourceform.SourceParentSharedReferenceReaders{}
		}
		return sourceform.SourceParentSharedReferenceReaders{
			Site:    refs.siteCodes,
			Region:  refs.regionCodes,
			Parent:  refs.parentCodes,
			Geology: refs.geologyCodes,
			Bec:     refs.bec,
		}
	}

	// Session-scoped PlotService read delegates

	r.register(svc, "CanEditMasterBEC", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		return false, nil
	})

	r.register(svc, "GetHeaderCapabilities", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		plots, err := lease.Context.Plots.WithRequestContext(c.ctx)
		if err != nil {
			return nil, err
		}
		return plots.GetHeaderCapabilities()
	})

	r.register(svc, "GetChildCapabilities", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		kind, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		plots, err := lease.Context.Plots.WithRequestContext(c.ctx)
		if err != nil {
			return nil, err
		}
		return plots.GetChildCapabilities(kind)
	})

	r.register(svc, "GetPlot", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		plotNumber, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		plots, err := lease.Context.Plots.WithRequestContext(c.ctx)
		if err != nil {
			return nil, err
		}
		return plots.GetPlot(plotNumber)
	})

	r.register(svc, "ListVegRecords", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		plotNumber, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		plots, err := lease.Context.Plots.WithRequestContext(c.ctx)
		if err != nil {
			return nil, err
		}
		return plots.ListVegRecords(plotNumber)
	})

	r.register(svc, "ListHumusRecords", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		plotNumber, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		plots, err := lease.Context.Plots.WithRequestContext(c.ctx)
		if err != nil {
			return nil, err
		}
		return plots.ListHumusRecords(plotNumber)
	})

	r.register(svc, "ListMineralRecords", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		plotNumber, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		plots, err := lease.Context.Plots.WithRequestContext(c.ctx)
		if err != nil {
			return nil, err
		}
		return plots.ListMineralRecords(plotNumber)
	})

	r.register(svc, "ListOtherRecords", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		plotNumber, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		lease, _, err := c.acquireSessionLease()
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		plots, err := lease.Context.Plots.WithRequestContext(c.ctx)
		if err != nil {
			return nil, err
		}
		return plots.ListOtherRecords(plotNumber)
	})

	// SIVI read-only original & reference endpoints

	r.register(svc, "GetSIVIParentSharedOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sourceform.NewSourceParentSharedService(lease.Context)
		if err != nil {
			return nil, err
		}
		s.References = buildSIVISharedReaders(c.server.refs)
		return s.GetOriginal(c.ctx, contextID, plot)
	})

	r.register(svc, "GetSIVIParentSharedReferences", "rpc", true, func(c *rpcCall) (any, error) {
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
		zone, err := decodeArg[vprocore.ProjectMetadataCell](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := sourceform.NewSourceParentSharedService(lease.Context)
		if err != nil {
			return nil, err
		}
		s.References = buildSIVISharedReaders(c.server.refs)
		return s.GetReferences(c.ctx, contextID, plot, zone)
	})

	r.register(svc, "GetSIVICoverOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sivi.NewSIVICoverService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, extended)
	})

	r.register(svc, "GetSIVICombinedOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sivi.NewSIVICombinedService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, extended)
	})

	r.register(svc, "GetSIVICollectedOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sivi.NewSIVICollectedService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, extended)
	})

	r.register(svc, "GetSIVISpeciesOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sourceform.NewSIVISpeciesService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, extended)
	})

	r.register(svc, "GetSIVISpeciesReferences", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sourceform.NewSIVISpeciesService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReferences(c.ctx, contextID, plot)
	})

	r.register(svc, "GetSIVIIdentityOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sivi.NewSIVIIdentityService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, extended)
	})

	r.register(svc, "GetSIVICreationReferences", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := sivi.NewSIVICreationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReferences(c.ctx, contextID, plot)
	})

	// Two-Page read-only original & reference endpoints

	r.register(svc, "GetTwoPageParentExtraOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageParentExtraService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageParentCommonOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageParentCommonService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageParentEntryOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageParentEntryService(lease.Context, buildTwoPageEntryReaders(c.server.refs))
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageParentEntryReferences", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		filters, err := decodeArg[twopage.TwoPageEntryReferenceFilters](c, 3)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageParentEntryService(lease.Context, buildTwoPageEntryReaders(c.server.refs))
		if err != nil {
			return nil, err
		}
		return s.GetReferences(c.ctx, contextID, plot, form, filters)
	})

	r.register(svc, "GetTwoPageSoilOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageSoilService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageSoilReferences", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageSoilService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReferences(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageVegetationOriginal", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOriginal(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageVegetationSpeciesReferences", "rpc", true, func(c *rpcCall) (any, error) {
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
		form, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := twopage.NewTwoPageVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetSpeciesReferences(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageProjectMetadataReview", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := classification.NewTwoPageProjectMetadataService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID, plot, offset, limit)
	})

	// Reference picklist lookup delegates

	r.register(svc, "GetAllLists", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.references == nil {
			return nil, errors.New("reference catalogue is unavailable")
		}
		return c.server.refs.references.GetAllLists(c.ctx)
	})

	r.register(svc, "GetListItems", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		listName, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.references == nil {
			return nil, errors.New("reference catalogue is unavailable")
		}
		return c.server.refs.references.GetListItems(c.ctx, listName)
	})

	r.register(svc, "GetSpecies", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		code, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.references == nil {
			return nil, errors.New("reference catalogue is unavailable")
		}
		return c.server.refs.references.GetSpecies(c.ctx, code)
	})

	r.register(svc, "SearchSpecies", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		query, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		limit, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.references == nil {
			return nil, errors.New("reference catalogue is unavailable")
		}
		return c.server.refs.references.SearchSpecies(c.ctx, query, limit)
	})

	r.register(svc, "ListExposureChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.siteCodes == nil {
			return nil, errors.New("site code catalogue is unavailable")
		}
		return c.server.refs.siteCodes.ListExposureChoices(c.ctx)
	})

	r.register(svc, "ListSiteDisturbanceChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.siteCodes == nil {
			return nil, errors.New("site code catalogue is unavailable")
		}
		return c.server.refs.siteCodes.ListSiteDisturbanceChoices(c.ctx)
	})

	r.register(svc, "ListGreatGroupChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.soilCodes == nil {
			return nil, errors.New("soil code catalogue is unavailable")
		}
		return c.server.refs.soilCodes.ListGreatGroupChoices(c.ctx)
	})

	r.register(svc, "ListSubgroupChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.soilCodes == nil {
			return nil, errors.New("soil code catalogue is unavailable")
		}
		return c.server.refs.soilCodes.ListSubgroupChoices(c.ctx)
	})

	r.register(svc, "ListParentCodeChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		listName, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.parentCodes == nil {
			return nil, errors.New("parent code catalogue is unavailable")
		}
		return c.server.refs.parentCodes.ListChoices(c.ctx, listName)
	})

	r.register(svc, "ListBedrockChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.geologyCodes == nil {
			return nil, errors.New("geology code catalogue is unavailable")
		}
		return c.server.refs.geologyCodes.ListBedrockChoices(c.ctx)
	})

	r.register(svc, "ListEcosectionChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.regionCodes == nil {
			return nil, errors.New("region code catalogue is unavailable")
		}
		return c.server.refs.regionCodes.ListEcosectionChoices(c.ctx)
	})

	r.register(svc, "ListRegionChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.regionCodes == nil {
			return nil, errors.New("region code catalogue is unavailable")
		}
		return c.server.refs.regionCodes.ListRegionChoices(c.ctx)
	})

	r.register(svc, "ListPlotQualityChoices", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		if c.server.refs == nil || c.server.refs.quality == nil {
			return nil, errors.New("plot quality catalogue is unavailable")
		}
		return c.server.refs.quality.ListPlotQualityChoices(c.ctx)
	})

	// LMH25 (2023) Pedon / Substrate / rSMR / rSNR diagnostics

	r.register(svc, "EvaluatePlotDiagnostics", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		header, err := decodeArg[vprocore.FS882Header](c, 0)
		if err != nil {
			return nil, err
		}
		humus, err := decodeArg[[]vprocore.HumusRecord](c, 1)
		if err != nil {
			return nil, err
		}
		mineral, err := decodeArg[[]vprocore.MineralRecord](c, 2)
		if err != nil {
			return nil, err
		}
		return lmh25rules.EvaluatePlotDiagnostics(header, humus, mineral), nil
	})

	r.register(svc, "EvaluateStoredPlotDiagnostics", "rpc", true, func(c *rpcCall) (any, error) {
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
		return lmh25rules.EvaluateStoredPlotDiagnostics(lease.Context, c.ctx, contextID, plotNumber)
	})

	r.register(svc, "GetPlotMensuration", "rpc", true, func(c *rpcCall) (any, error) {
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
		mens, err := plotentry.NewMensurationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return mens.GetPlotMensuration(c.ctx, contextID, plotNumber)
	})
}
