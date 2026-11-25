package main

import (
	"archive/zip"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"

	"github.com/boostao/vpro/app/internal/envreport"
	"github.com/boostao/vpro/app/internal/rsidecar"
)

func (r *RPCRouter) registerEnvReportHandlers() {
	const svc = "EnvironmentReportService"

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

	r.register(svc, "GetLongEnvironmentPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return envreport.NewLongEnvironmentPreferencesService(lease.Context).GetLongEnvironmentPreferences(c.ctx, contextID)
	})

	r.register(svc, "SaveLongEnvironmentPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return envreport.NewLongEnvironmentPreferencesService(lease.Context).SaveLongEnvironmentPreferences(c.ctx, contextID, requestJSON), nil
	})

	r.register(svc, "GetEnvironmentWorkbookReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := envreport.NewEnvironmentWorkbookService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "ExportReviewedEnvironmentWorkbook", "download", false, func(c *rpcCall) (any, error) {
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

			s, err := envreport.NewEnvironmentWorkbookService(lease.Context)
			if err != nil {
				return nil, err
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-environment-report.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome, err := s.ExportReviewed(ctx, contextID, rewritten)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "environment workbook export did not produce a file"
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

	r.register(svc, "GetSiteUnitSummaryPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return envreport.NewSiteUnitSummaryPreferencesService(lease.Context).GetSiteUnitSummaryPreferences(c.ctx, contextID)
	})

	r.register(svc, "SaveSiteUnitSummaryPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return envreport.NewSiteUnitSummaryPreferencesService(lease.Context).SaveSiteUnitSummaryPreferences(c.ctx, contextID, requestJSON), nil
	})

	r.register(svc, "GetFullSiteUnitSummaryPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return envreport.NewSiteUnitSummaryPreferencesService(lease.Context).GetFullSiteUnitSummaryPreferences(c.ctx, contextID)
	})

	r.register(svc, "SaveFullSiteUnitSummaryPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return envreport.NewSiteUnitSummaryPreferencesService(lease.Context).SaveFullSiteUnitSummaryPreferences(c.ctx, contextID, requestJSON), nil
	})

	r.register(svc, "GetSiteUnitSummaryWorkbookReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := envreport.NewSiteUnitSummaryWorkbookService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "ExportReviewedSiteUnitSummaryWorkbook", "download", false, func(c *rpcCall) (any, error) {
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

			s, err := envreport.NewSiteUnitSummaryWorkbookService(lease.Context)
			if err != nil {
				return nil, err
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-site-unit-summary.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome, err := s.ExportReviewed(ctx, contextID, rewritten)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "site unit summary workbook export did not produce a file"
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

	r.register(svc, "GetSiteUnitSummaryExtendedWorkbookReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := envreport.NewSiteUnitSummaryExtendedWorkbookService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "ExportReviewedSiteUnitSummaryExtendedWorkbook", "download", false, func(c *rpcCall) (any, error) {
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

			s, err := envreport.NewSiteUnitSummaryExtendedWorkbookService(lease.Context)
			if err != nil {
				return nil, err
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-site-unit-summary-extended.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome, err := s.ExportReviewed(ctx, contextID, rewritten)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "extended site unit summary workbook export did not produce a file"
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

	r.register(svc, "GetSubzoneMatrixPreview", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := envreport.NewSubzoneMatrixService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetPreview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "GetSubzoneMatrixReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := envreport.NewSubzoneMatrixService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID)
	})

	r.register(svc, "ExportReviewedSubzoneMatrix", "download", false, func(c *rpcCall) (any, error) {
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

			s, err := envreport.NewSubzoneMatrixService(lease.Context)
			if err != nil {
				return nil, err
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-subzone-matrix.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome, err := s.ExportReviewed(ctx, contextID, rewritten)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "subzone matrix export did not produce a file"
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

	// --- Read-Only R Sidecar (guarded by VPRO_WEB_R_CONCURRENCY semaphore) ---

	r.register(svc, "DetectRRuntime", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		return c.withRSlot(func(ctx context.Context) (any, error) {
			return rsidecar.DetectRRuntime(ctx, c.server.rRuntimeOptions()...)
		})
	})

	r.register(svc, "GetCachedPlotClimate", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		refPeriod, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return rsidecar.GetCachedPlotClimate(c.ctx, lease.Context, contextID, refPeriod)
	})

	r.register(svc, "ComputePlotClimateAndDualEdatopic", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[rsidecar.ClimateEdatopicRequest](c, 1)
		if err != nil {
			return nil, err
		}
		return c.withRSlot(func(ctx context.Context) (any, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			return rsidecar.ComputePlotClimateAndDualEdatopic(ctx, lease.Context, contextID, req, c.server.rRuntimeOptions()...)
		})
	})

	r.register(svc, "RunMultivariateClustering", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[rsidecar.ClusteringRequest](c, 1)
		if err != nil {
			return nil, err
		}
		return c.withRSlot(func(ctx context.Context) (any, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()
			return rsidecar.RunMultivariateClustering(ctx, lease.Context, contextID, req, c.server.rRuntimeOptions()...)
		})
	})

	r.register(svc, "RenderQuartoGuide", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[rsidecar.QuartoGuideRequest](c, 1)
		if err != nil {
			return nil, err
		}
		return c.withRSlot(func(ctx context.Context) (any, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			htmlFilename := sanitizeDownloadFilename(lease.Dataset.Project + "-bec-guide.html")
			htmlPath, dirPath, cleanup, err := c.server.downloads.MintTempPath(htmlFilename)
			if err != nil {
				return nil, err
			}
			req.DestinationPath = htmlPath // Strictly ignore client-supplied destinationPath.

			outcome, err := rsidecar.RenderQuartoGuide(ctx, lease.Context, contextID, req, c.server.rRuntimeOptions()...)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.HTMLPath == "" {
				cleanup()
				return nil, errors.New("Quarto guide rendering did not produce an HTML artifact")
			}

			servePath := outcome.HTMLPath
			serveName := htmlFilename
			if outcome.PDFPath != "" {
				if info, statErr := os.Stat(outcome.PDFPath); statErr == nil && info.Mode().IsRegular() {
					zipFilename := sanitizeDownloadFilename(lease.Dataset.Project + "-bec-guide-bundle.zip")
					zipPath := filepath.Join(dirPath, zipFilename)
					if zErr := packageGuideBundleZIP(zipPath, outcome.HTMLPath, outcome.PDFPath); zErr == nil {
						servePath = zipPath
						serveName = zipFilename
					}
				}
			}

			_, dlURL, safeName, err := c.server.downloads.Register(servePath, dirPath, serveName)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome.HTMLPath = filepath.Base(outcome.HTMLPath)
			if outcome.PDFPath != "" {
				outcome.PDFPath = filepath.Base(outcome.PDFPath)
			}
			return &downloadResult{
				Outcome:     outcome,
				DownloadURL: dlURL,
				Filename:    safeName,
			}, nil
		})
	})
}

func packageGuideBundleZIP(zipPath string, files ...string) error {
	out, err := os.Create(zipPath)
	if err != nil {
		return err
	}
	zw := zip.NewWriter(out)
	for _, srcPath := range files {
		if srcPath == "" {
			continue
		}
		src, err := os.Open(srcPath)
		if err != nil {
			_ = zw.Close()
			_ = out.Close()
			return err
		}
		entry, err := zw.Create(filepath.Base(srcPath))
		if err != nil {
			_ = src.Close()
			_ = zw.Close()
			_ = out.Close()
			return err
		}
		if _, err := io.Copy(entry, src); err != nil {
			_ = src.Close()
			_ = zw.Close()
			_ = out.Close()
			return err
		}
		_ = src.Close()
	}
	if err := zw.Close(); err != nil {
		_ = out.Close()
		return err
	}
	return out.Close()
}
