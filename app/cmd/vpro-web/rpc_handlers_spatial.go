package main

import (
	"context"
	"errors"

	"github.com/boostao/vpro/app/internal/spatial"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func (r *RPCRouter) registerSpatialHandlers() {
	const svc = "SpatialService"

	newCoords := func(c *rpcCall) (*vprocore.CoordinateService, error) {
		if c.server.refs == nil {
			return nil, errors.New("coordinate service is unavailable")
		}
		return vprocore.NewCoordinateServiceInternal(c.server.refs.configDir, c.session.Prefs)
	}

	rewritePMTilesManifestURLs := func(c *rpcCall, m spatial.PMTilesManifest) spatial.PMTilesManifest {
		base := c.server.pmtilesBaseURL()
		if base == "" {
			return m
		}
		for k, v := range m.Archives {
			v.URL = base + "/" + v.Name
			m.Archives[k] = v
		}
		for i := range m.Ordered {
			m.Ordered[i].URL = base + "/" + m.Ordered[i].Name
		}
		return m
	}

	r.register(svc, "GetCoordinateMode", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		coords, err := newCoords(c)
		if err != nil {
			return nil, err
		}
		return coords.GetCoordinateModeContext(c.ctx)
	})

	r.register(svc, "SetCoordinateMode", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		mode, err := decodeArg[vprocore.CoordinateMode](c, 0)
		if err != nil {
			return nil, err
		}
		coords, err := newCoords(c)
		if err != nil {
			return nil, err
		}
		if err := coords.SetCoordinateModeContext(c.ctx, mode); err != nil {
			return nil, err
		}
		return voidResult, nil
	})

	r.register(svc, "DecomposeCoordinate", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		value, err := decodeArg[*float64](c, 0)
		if err != nil {
			return nil, err
		}
		mode, err := decodeArg[vprocore.CoordinateMode](c, 1)
		if err != nil {
			return nil, err
		}
		coords, err := newCoords(c)
		if err != nil {
			return nil, err
		}
		return coords.DecomposeCoordinate(value, mode)
	})

	r.register(svc, "ConvertCoordinate", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		axis, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		mode, err := decodeArg[vprocore.CoordinateMode](c, 1)
		if err != nil {
			return nil, err
		}
		parts, err := decodeArg[vprocore.CoordinateParts](c, 2)
		if err != nil {
			return nil, err
		}
		coords, err := newCoords(c)
		if err != nil {
			return nil, err
		}
		return coords.ConvertCoordinate(axis, mode, parts)
	})

	r.register(svc, "GetGoogleEarthDescriptionFields", "rpc", true, func(c *rpcCall) (any, error) {
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
		return spatial.NewGoogleEarthReviewService(lease.Context).GetGoogleEarthDescriptionFields(c.ctx, contextID)
	})

	r.register(svc, "GetGoogleEarthReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		return spatial.NewGoogleEarthReviewService(lease.Context).GetGoogleEarthReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "GetGoogleEarthKMLReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		return spatial.NewGoogleEarthKMLService(lease.Context).GetGoogleEarthKMLReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "GetGoogleEarthKMLExportReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		return spatial.NewGoogleEarthKMLExportService(lease.Context).GetGoogleEarthKMLExportReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "ExportReviewedGoogleEarthKML", "download", false, func(c *rpcCall) (any, error) {
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
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-plots.kml")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}

			outcome, err := spatial.NewGoogleEarthKMLExportService(lease.Context).ExportReviewedGoogleEarthKML(ctx, contextID, rewritten)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "Google Earth KML export did not produce a file"
				if outcome != nil && outcome.ErrorMessage != "" {
					msg = outcome.ErrorMessage
				}
				return nil, errors.New(msg)
			}
			_, dlURL, safeName, err := c.server.downloads.Register(outcome.Path, dirPath, filename)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome.Path = safeName
			outcome.RequestedDestination = safeName
			return &downloadResult{
				Outcome:     outcome,
				DownloadURL: dlURL,
				Filename:    safeName,
			}, nil
		})
	})

	r.register(svc, "GetGoogleEarthPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return spatial.NewGoogleEarthPreferencesService(lease.Context).GetGoogleEarthPreferences(c.ctx, contextID)
	})

	r.register(svc, "SaveGoogleEarthPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return spatial.NewGoogleEarthPreferencesService(lease.Context).SaveGoogleEarthPreferences(c.ctx, contextID, requestJSON), nil
	})

	r.register(svc, "GetTwoPageGoogleEarthOptions", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := spatial.NewTwoPageGoogleEarthService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetOptions(c.ctx, contextID, plot, form)
	})

	r.register(svc, "GetTwoPageGoogleEarthReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		requestJSON, err := decodeArg[string](c, 3)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := spatial.NewTwoPageGoogleEarthService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID, plot, form, requestJSON)
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

	r.register(svc, "GetPMTilesManifest", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		m := spatial.BuildPMTilesManifest(c.server.cfg.PMTilesDir, c.server.pmtilesExtraDirs()...)
		return rewritePMTilesManifestURLs(c, m), nil
	})

	r.register(svc, "ProjectNAD83LatLonToUTM", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		lat, err := decodeArg[float64](c, 0)
		if err != nil {
			return nil, err
		}
		lon, err := decodeArg[float64](c, 1)
		if err != nil {
			return nil, err
		}
		normLat, normLon, _, _ := spatial.NormalizeBCWesternCoordinates(lat, lon)
		z, e, n, err := spatial.ProjectNAD83LatLonToUTM(normLat, normLon)
		if err != nil {
			return nil, err
		}
		return spatial.NAD83UTMProjection{
			Zone:        z,
			Easting:     e,
			Northing:    n,
			NtsMapSheet: spatial.ComputeBCGSMapSheet(normLat, normLon),
		}, nil
	})

	r.register(svc, "ProjectNAD83UTMToLatLon", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		zone, err := decodeArg[int](c, 0)
		if err != nil {
			return nil, err
		}
		easting, err := decodeArg[float64](c, 1)
		if err != nil {
			return nil, err
		}
		northing, err := decodeArg[float64](c, 2)
		if err != nil {
			return nil, err
		}
		lat, lon, err := spatial.ProjectNAD83UTMToLatLon(zone, easting, northing)
		if err != nil {
			return nil, err
		}
		return spatial.NAD83LatLonProjection{
			Latitude:    lat,
			Longitude:   lon,
			NtsMapSheet: spatial.ComputeBCGSMapSheet(lat, lon),
		}, nil
	})

	r.register(svc, "ComputeBCGSMapSheet", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		lat, err := decodeArg[float64](c, 0)
		if err != nil {
			return nil, err
		}
		lon, err := decodeArg[float64](c, 1)
		if err != nil {
			return nil, err
		}
		return spatial.ComputeBCGSMapSheet(lat, lon), nil
	})

	r.register(svc, "EvaluatePlotGeodesy", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(1); err != nil {
			return nil, err
		}
		input, err := decodeArg[spatial.PlotGeodesyInput](c, 0)
		if err != nil {
			return nil, err
		}
		return spatial.EvaluatePlotGeodesy(input), nil
	})

	r.register(svc, "SuggestSpatialAttributes", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		lat, err := decodeArg[float64](c, 0)
		if err != nil {
			return nil, err
		}
		lon, err := decodeArg[float64](c, 1)
		if err != nil {
			return nil, err
		}
		if c.server.attributor != nil {
			return c.server.attributor.SuggestSpatialAttributes(lat, lon)
		}
		return spatial.SuggestSpatialAttributes(lat, lon)
	})

	r.register(svc, "BatchAuditSpatialQA", "rpc", true, func(c *rpcCall) (any, error) {
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
		return spatial.BatchAuditSpatialQA(c.ctx, lease.Context, contextID, c.server.attributor)
	})

	r.register(svc, "GetSpatialWorkbenchPayload", "rpc", true, func(c *rpcCall) (any, error) {
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
		payload, err := spatial.GetSpatialWorkbenchPayload(c.ctx, lease.Context, contextID, c.server.cfg.PMTilesDir, c.server.pmtilesExtraDirs(), c.server.attributor)
		if err != nil {
			return nil, err
		}
		if payload != nil {
			payload.Manifest = rewritePMTilesManifestURLs(c, payload.Manifest)
		}
		return payload, nil
	})

	r.register(svc, "GetSpatialPlotsFlatGeobuf", "rpc", true, func(c *rpcCall) (any, error) {
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
		return spatial.GetSpatialPlotsFlatGeobuf(c.ctx, lease.Context, contextID, c.server.attributor)
	})

	r.register(svc, "SelectPlotsInPolygonAOI", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[spatial.SpatialAOISelectionRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return spatial.SelectPlotsInPolygonAOI(c.ctx, lease.Context, contextID, req, c.server.attributor)
	})

	r.register(svc, "GetBECMasterFilterOptions", "rpc", true, func(c *rpcCall) (any, error) {
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
		return spatial.GetBECMasterFilterOptions(c.ctx, lease.Context, contextID)
	})

	r.register(svc, "FilterBECMasterPlots", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[spatial.BECMasterFilterRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return spatial.FilterBECMasterPlots(c.ctx, lease.Context, contextID, req)
	})
}
