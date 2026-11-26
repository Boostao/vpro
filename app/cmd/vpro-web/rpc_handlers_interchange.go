package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/boostao/vpro/app/internal/interchange"
	"github.com/boostao/vpro/app/internal/lumping"
)

func (r *RPCRouter) registerImportExportHandlers() {
	const svc = "ImportExportService"

	// --- Table CSV Review & Archive Download ---

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

	r.register(svc, "GetTableCSVArchiveReview", "rpc", true, func(c *rpcCall) (any, error) {
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
		return interchange.NewTableCSVArchiveService(lease.Context).GetTableCSVArchiveReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "ExportReviewedTableCSVArchive", "download", false, func(c *rpcCall) (any, error) {
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

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-tables.zip")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}

			outcome, err := interchange.NewTableCSVArchiveService(lease.Context).ExportReviewedTableCSVArchive(ctx, contextID, rewritten)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "table CSV archive export did not produce a file"
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

	// --- Plot Label Regional Preview & PDF Review / Download ---

	r.register(svc, "GetPlotLabelRegionalPreview", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := interchange.NewPlotLabelRegionalService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetPreview(c.ctx, contextID, plot)
	})

	r.register(svc, "GetPlotLabelPDFReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		pdfSvc := interchange.NewPlotLabelPDFExportService(lease.Context)
		review, err := pdfSvc.GetReview(c.ctx, contextID, requestJSON)
		if err != nil {
			return nil, err
		}
		// Record stable session binding for the follow-up ExportReviewedPlotLabelPDF call.
		if review != nil && review.SessionID != "" {
			c.session.SetPlotLabelSessionID(review.SessionID)
		}
		return review, nil
	})

	r.register(svc, "ExportReviewedPlotLabelPDF", "download", false, func(c *rpcCall) (any, error) {
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

		// Parse request fields so we can validate session binding & extract plotNumber
		// while strictly overriding destination with a server-minted temp path.
		dec := json.NewDecoder(strings.NewReader(requestJSON))
		dec.UseNumber()
		var reqObj map[string]any
		if err := dec.Decode(&reqObj); err != nil || reqObj == nil {
			return nil, errBadRequest("invalid plot label PDF export request JSON")
		}
		plotNumber, _ := reqObj["plotNumber"].(string)
		clientSessionID, _ := reqObj["sessionId"].(string)
		if expected := c.session.PlotLabelSessionID(); expected != "" && clientSessionID != expected {
			return nil, errBadRequest("plot label PDF session mismatch; prepare a new review")
		}

		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			pdfSvc := interchange.NewPlotLabelPDFExportService(lease.Context)
			reviewReq, err := json.Marshal(map[string]string{"plotNumber": plotNumber})
			if err != nil {
				return nil, err
			}
			probe, err := pdfSvc.GetReview(ctx, contextID, string(reviewReq))
			if err != nil {
				return nil, err
			}

			filename := sanitizeDownloadFilename(fmt.Sprintf("%s-plot-%s-label.pdf", lease.Dataset.Project, plotNumber))
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}

			reqObj["destination"] = filePath // Strictly ignore any client-supplied destination.
			reqObj["sessionId"] = probe.SessionID
			rewrittenBytes, err := json.Marshal(reqObj)
			if err != nil {
				cleanup()
				return nil, err
			}

			outcome, err := pdfSvc.ExportReviewed(ctx, contextID, string(rewrittenBytes))
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "plot label PDF export did not produce a file"
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

	// --- Combine Species (*_Lump) Read-Only Discovery & Preview (with path traversal guards!) ---

	r.register(svc, "DiscoverLumpTables", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		externalPaths, err := decodeArg[[]string](c, 1)
		if err != nil {
			return nil, err
		}
		// Security guard: reject any client-supplied external filesystem paths.
		for _, p := range externalPaths {
			if strings.TrimSpace(p) != "" {
				return nil, errForbidden("external filesystem paths are not permitted for DiscoverLumpTables in web read-only mode")
			}
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lumping.DiscoverLumpTables(lease.Context, c.ctx, contextID, nil)
	})

	r.register(svc, "GetLumpTableRows", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		tableName, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		dbPath, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		// Security guard: never allow arbitrary host DB paths outside the verified snapshot.
		if err := c.guardSnapshotDBPath(dbPath, "dbPath"); err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lumping.GetLumpTableRows(lease.Context, c.ctx, contextID, tableName, dbPath)
	})

	r.register(svc, "PreviewLumpImpact", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		tableName, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		dbPath, err := decodeArg[string](c, 2)
		if err != nil {
			return nil, err
		}
		// Security guard: never allow arbitrary host DB paths outside the verified snapshot.
		if err := c.guardSnapshotDBPath(dbPath, "dbPath"); err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lumping.PreviewLumpImpact(lease.Context, c.ctx, contextID, tableName, dbPath)
	})

	r.register(svc, "ListLumpPresets", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		return lumping.ListLumpPresets(), nil
	})

	r.register(svc, "PreviewLumpSpec", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		spec, err := decodeArg[lumping.LumpSpec](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return lumping.PreviewLumpSpec(lease.Context, c.ctx, contextID, spec)
	})

	// --- Read-Only Interchange Downloads (strictly overriding DestinationPath!) ---

	r.register(svc, "ExportTurboVeg", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[interchange.TurboVegExportRequest](c, 1)
		if err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(req.LumpDBPath, "lumpDbPath"); err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			ext := ".xml"
			if strings.EqualFold(strings.TrimSpace(req.Format), "sqlite") {
				ext = ".sqlite"
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-turboveg" + ext)
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.DestinationPath = filePath

			outcome, err := interchange.ExportTurboVeg(lease.Context, ctx, contextID, req)
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

	r.register(svc, "ExportUserSpeciesList", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[interchange.UserSpeciesExportRequest](c, 1)
		if err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			ext := ".csv"
			if strings.EqualFold(strings.TrimSpace(req.Format), "json") {
				ext = ".json"
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-user-species" + ext)
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.DestinationPath = filePath

			outcome, err := interchange.ExportUserSpeciesList(lease.Context, ctx, contextID, req)
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

	r.register(svc, "ExportLongTidyCSV", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[interchange.LongTidyCSVRequest](c, 1)
		if err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(req.LumpDBPath, "lumpDbPath"); err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-vegetation-long.csv")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.DestinationPath = filePath

			outcome, err := interchange.ExportLongTidyCSV(lease.Context, ctx, contextID, req)
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

	r.register(svc, "ExportWideMatrixCSV", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[interchange.WideMatrixCSVRequest](c, 1)
		if err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(req.LumpDBPath, "lumpDbPath"); err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-vegetation-wide.csv")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.DestinationPath = filePath

			outcome, err := interchange.ExportWideMatrixCSV(lease.Context, ctx, contextID, req)
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

	r.register(svc, "ExportProjectRDS", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[interchange.RDSExportRequest](c, 1)
		if err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(req.LumpDBPath, "lumpDbPath"); err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + ".rds")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.DestinationPath = filePath

			outcome, err := interchange.ExportProjectRDS(lease.Context, ctx, contextID, req)
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

	r.register(svc, "ExportGeoPackage", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[interchange.GeoPackageExportRequest](c, 1)
		if err != nil {
			return nil, err
		}
		if err := c.guardSnapshotDBPath(req.LumpDBPath, "lumpDbPath"); err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-plots.gpkg")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.DestinationPath = filePath

			outcome, err := interchange.ExportGeoPackage(lease.Context, ctx, contextID, req)
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

	r.register(svc, "ExportVPro64Database", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[interchange.VPro64ExportRequest](c, 1)
		if err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-vpro64.db")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			// Strictly ignore client-supplied destinationPath and write inside VPRO_WEB_EXPORT_DIR/downloads.
			req.DestinationPath = filePath

			outcome, err := interchange.ExportVPro64Database(lease.Context, ctx, contextID, req)
			if err != nil {
				cleanup()
				return nil, err
			}
			_, dlURL, safeName, err := c.server.downloads.Register(outcome.DestinationPath, dirPath, filename)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome.DestinationPath = safeName
			return &downloadResult{
				Outcome:     outcome,
				DownloadURL: dlURL,
				Filename:    safeName,
			}, nil
		})
	})
}
