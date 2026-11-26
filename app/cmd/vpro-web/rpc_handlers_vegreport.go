package main

import (
	"context"
	"errors"

	"github.com/boostao/vpro/app/internal/vegreport"
	"github.com/boostao/vpro/app/internal/vprocore"
)

func (r *RPCRouter) registerVegReportHandlers() {
	const svc = "VegetationReportService"

	buildSummaryWorkbook := func(ctxSvc *vprocore.ContextService) (*vegreport.SummaryVegetationWorkbookService, error) {
		summary, err := vegreport.NewSummaryVegetationService(ctxSvc)
		if err != nil {
			return nil, err
		}
		summaryEnv, err := vegreport.NewSummaryVegetationEnvironmentalService(summary)
		if err != nil {
			return nil, err
		}
		summaryEnvLF, err := vegreport.NewSummaryVegetationEnvironmentalLifeformService(summaryEnv)
		if err != nil {
			return nil, err
		}
		return vegreport.NewSummaryVegetationWorkbookService(summaryEnvLF)
	}

	// --- Summary Vegetation previews & workbook ---

	r.register(svc, "PreviewSummaryVegetation", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		average, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		display, err := decodeArg[int](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.Preview(c.ctx, contextID, average, display)
	})

	r.register(svc, "PreviewSummaryVegetationClass", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(4); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		average, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		display, err := decodeArg[int](c, 2)
		if err != nil {
			return nil, err
		}
		showClass, err := decodeArg[int](c, 3)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.PreviewClass(c.ctx, contextID, average, display, showClass)
	})

	r.register(svc, "PreviewSummaryVegetationGrouped", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(3); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		average, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		groupAndOrder, err := decodeArg[int](c, 2)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.PreviewGrouped(c.ctx, contextID, average, groupAndOrder)
	})

	r.register(svc, "PreviewSummaryVegetationGroupedDisplay", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(5); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		average, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		groupAndOrder, err := decodeArg[int](c, 2)
		if err != nil {
			return nil, err
		}
		display, err := decodeArg[int](c, 3)
		if err != nil {
			return nil, err
		}
		showClass, err := decodeArg[int](c, 4)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.PreviewGroupedDisplay(c.ctx, contextID, average, groupAndOrder, display, showClass)
	})

	r.register(svc, "PreviewSummaryVegetationWithPreferences", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.PreviewWithPreferences(c.ctx, contextID)
	})

	r.register(svc, "PreviewSummaryVegetationConfigured", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.PreviewConfigured(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "PreviewSummaryVegetationEnvironmental", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(4); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		average, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		display, err := decodeArg[int](c, 2)
		if err != nil {
			return nil, err
		}
		showClass, err := decodeArg[int](c, 3)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		summary, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		envSvc, err := vegreport.NewSummaryVegetationEnvironmentalService(summary)
		if err != nil {
			return nil, err
		}
		return envSvc.PreviewEnvironmental(c.ctx, contextID, average, display, showClass)
	})

	r.register(svc, "PreviewSummaryVegetationEnvironmentalNumeric", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(4); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		average, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		display, err := decodeArg[int](c, 2)
		if err != nil {
			return nil, err
		}
		showClass, err := decodeArg[int](c, 3)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		summary, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		envSvc, err := vegreport.NewSummaryVegetationEnvironmentalService(summary)
		if err != nil {
			return nil, err
		}
		return envSvc.PreviewEnvironmentalNumeric(c.ctx, contextID, average, display, showClass)
	})

	r.register(svc, "PreviewSummaryVegetationEnvironmentalLifeform", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(4); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		average, err := decodeArg[int](c, 1)
		if err != nil {
			return nil, err
		}
		display, err := decodeArg[int](c, 2)
		if err != nil {
			return nil, err
		}
		showClass, err := decodeArg[int](c, 3)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		summary, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		envSvc, err := vegreport.NewSummaryVegetationEnvironmentalService(summary)
		if err != nil {
			return nil, err
		}
		lfSvc, err := vegreport.NewSummaryVegetationEnvironmentalLifeformService(envSvc)
		if err != nil {
			return nil, err
		}
		return lfSvc.PreviewEnvironmentalLifeform(c.ctx, contextID, average, display, showClass)
	})

	r.register(svc, "GetSummaryVegetationWorkbookReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		wb, err := buildSummaryWorkbook(lease.Context)
		if err != nil {
			return nil, err
		}
		return wb.GetReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "GetSummaryVegetationWorkbookReviewFromPreferences", "rpc", false, func(c *rpcCall) (any, error) {
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
		wb, err := buildSummaryWorkbook(lease.Context)
		if err != nil {
			return nil, err
		}
		return wb.GetReviewFromPreferences(c.ctx, contextID)
	})

	r.register(svc, "ExportReviewedSummaryVegetationWorkbook", "download", false, func(c *rpcCall) (any, error) {
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

			wb, err := buildSummaryWorkbook(lease.Context)
			if err != nil {
				return nil, err
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-summary-vegetation.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}
			outcome, err := wb.ExportReviewed(ctx, contextID, rewritten)
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "summary vegetation workbook export did not produce a file"
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

	// --- Summary Vegetation Preferences & Field Lists ---

	r.register(svc, "GetSummaryVegetationPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationPreferencesService(lease.Context).GetSummaryVegetationPreferences(c.ctx, contextID)
	})

	r.register(svc, "SaveSummaryVegetationPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationPreferencesService(lease.Context).SaveSummaryVegetationPreferences(c.ctx, contextID, requestJSON), nil
	})

	r.register(svc, "GetSummaryVegetationQualityPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationQualityPreferencesService(lease.Context).GetSummaryVegetationQualityPreferences(c.ctx, contextID)
	})

	r.register(svc, "SaveSummaryVegetationQualityPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationQualityPreferencesService(lease.Context).SaveSummaryVegetationQualityPreferences(c.ctx, contextID, requestJSON), nil
	})

	r.register(svc, "GetSummaryVegetationPresentationPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationPresentationPreferencesService(lease.Context).GetSummaryVegetationPresentationPreferences(c.ctx, contextID)
	})

	r.register(svc, "SaveSummaryVegetationPresentationPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationPresentationPreferencesService(lease.Context).SaveSummaryVegetationPresentationPreferences(c.ctx, contextID, requestJSON), nil
	})

	r.register(svc, "GetSummaryVegetationFieldList", "rpc", true, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationFieldListService(lease.Context).GetSummaryVegetationFieldList(c.ctx, contextID)
	})

	r.register(svc, "GetSummaryVegetationFieldListIndex", "rpc", true, func(c *rpcCall) (any, error) {
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
		return vegreport.NewSummaryVegetationFieldListService(lease.Context).GetSummaryVegetationFieldListIndex(c.ctx, contextID)
	})

	// --- Long Vegetation options, previews, preferences (all in-memory per session!) ---

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

	r.register(svc, "GetLongVegetationTabPreferences", "prefs", false, func(c *rpcCall) (any, error) {
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
		return vegreport.NewLongVegetationAllPreferencesService(lease.Context).GetAll(c.ctx, contextID)
	})

	r.register(svc, "SaveLongVegetationTabPreferences", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationTabPreferencesSaveRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return vegreport.NewLongVegetationAllPreferencesService(lease.Context).SaveTab(c.ctx, contextID, req), nil
	})

	registerLVPrefPair := func(
		getName, saveName string,
		getFn func(*vegreport.LongVegetationAllPreferencesService, context.Context, string) (any, error),
		saveFn func(*vegreport.LongVegetationAllPreferencesService, context.Context, string, string) any,
	) {
		r.register(svc, getName, "prefs", false, func(c *rpcCall) (any, error) {
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
			return getFn(vegreport.NewLongVegetationAllPreferencesService(lease.Context), c.ctx, contextID)
		})
		r.register(svc, saveName, "prefs", false, func(c *rpcCall) (any, error) {
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
			return saveFn(vegreport.NewLongVegetationAllPreferencesService(lease.Context), c.ctx, contextID, requestJSON), nil
		})
	}

	registerLVPrefPair(
		"GetLongVegetationPreferences", "SaveLongVegetationPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Title.GetLongVegetationPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Title.SaveLongVegetationPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationStatisticsPreferences", "SaveLongVegetationStatisticsPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Statistics.GetLongVegetationStatisticsPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Statistics.SaveLongVegetationStatisticsPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationSwitchPreferences", "SaveLongVegetationSwitchPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Switch.GetLongVegetationSwitchPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Switch.SaveLongVegetationSwitchPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationThresholdPreferences", "SaveLongVegetationThresholdPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Threshold.GetLongVegetationThresholdPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Threshold.SaveLongVegetationThresholdPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationGroupPreferences", "SaveLongVegetationGroupPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Group.GetLongVegetationGroupPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Group.SaveLongVegetationGroupPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationQualityNullPreferences", "SaveLongVegetationQualityNullPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.QualityNull.GetLongVegetationQualityNullPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.QualityNull.SaveLongVegetationQualityNullPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationQualityMinimumPreferences", "SaveLongVegetationQualityMinimumPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.QualityMin.GetLongVegetationQualityMinimumPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.QualityMin.SaveLongVegetationQualityMinimumPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationNamingPreferences", "SaveLongVegetationNamingPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Naming.GetLongVegetationNamingPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Naming.SaveLongVegetationNamingPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationSelectedFieldPreferences", "SaveLongVegetationSelectedFieldPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.SelectedField.GetLongVegetationSelectedFieldPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.SelectedField.SaveLongVegetationSelectedFieldPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationEnforcementPreferences", "SaveLongVegetationEnforcementPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Enforcement.GetLongVegetationEnforcementPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Enforcement.SaveLongVegetationEnforcementPreferences(ctx, id, raw)
		},
	)
	registerLVPrefPair(
		"GetLongVegetationUnitPreferences", "SaveLongVegetationUnitPreferences",
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id string) (any, error) {
			return s.Unit.GetLongVegetationUnitPreferences(ctx, id)
		},
		func(s *vegreport.LongVegetationAllPreferencesService, ctx context.Context, id, raw string) any {
			return s.Unit.SaveLongVegetationUnitPreferences(ctx, id, raw)
		},
	)

	// --- Long Vegetation Selected-Unit Selection & Project Scope (per-session carrier) ---

	r.register(svc, "BuildLongVegetationSelectedUnitSelection", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		revision, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out *vegreport.LongVegetationSelectedUnitSelection
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationSelectedUnitSelectionService(carrier).BuildLongVegetationSelectedUnitSelection(c.ctx, contextID, revision)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "GetLongVegetationSelectedUnitSelection", "rpc", false, func(c *rpcCall) (any, error) {
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
		var out *vegreport.LongVegetationSelectedUnitSelection
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationSelectedUnitSelectionService(carrier).GetLongVegetationSelectedUnitSelection(c.ctx, contextID)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "SetLongVegetationSelectedUnitFields", "prefs", false, func(c *rpcCall) (any, error) {
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
		var out *vegreport.LongVegetationSelectedUnitSelection
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationSelectedUnitSelectionService(carrier).SetLongVegetationSelectedUnitFields(c.ctx, contextID, requestJSON)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "BuildLongVegetationProjectScope", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		revision, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out *vegreport.LongVegetationReportScope
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).BuildLongVegetationProjectScope(c.ctx, contextID, revision)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "GetLongVegetationProjectFieldDefinitions", "rpc", false, func(c *rpcCall) (any, error) {
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
		var out *vegreport.LongVegetationProjectFieldDefinitions
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).GetLongVegetationProjectFieldDefinitions(c.ctx, contextID)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "GetLongVegetationProjectOptions", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationProjectReadRequest](c, 1)
		if err != nil {
			return nil, err
		}
		raw, err := marshalTypedJSON(req)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out vegreport.LongVegetationProjectOptions
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).GetLongVegetationProjectOptions(c.ctx, contextID, raw)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "GetLongVegetationProjectUnitPreferences", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationProjectReadRequest](c, 1)
		if err != nil {
			return nil, err
		}
		raw, err := marshalTypedJSON(req)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out vegreport.LongVegetationProjectUnitPreferences
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).GetLongVegetationProjectUnitPreferences(c.ctx, contextID, raw)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "GetLongVegetationReportScope", "rpc", false, func(c *rpcCall) (any, error) {
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
		var out *vegreport.LongVegetationReportScope
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).GetLongVegetationReportScope(c.ctx, contextID)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "PreviewLongVegetationProject", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationProjectReadRequest](c, 1)
		if err != nil {
			return nil, err
		}
		raw, err := marshalTypedJSON(req)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out vegreport.LongVegetationProjectPreview
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).PreviewLongVegetationProject(c.ctx, contextID, raw)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "SaveLongVegetationProjectUnits", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationProjectUnitRequest](c, 1)
		if err != nil {
			return nil, err
		}
		raw, err := marshalTypedJSON(req)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out vegreport.LongVegetationProjectUnitOutcome
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			out = vegreport.NewLongVegetationReportScopeService(carrier).SaveLongVegetationProjectUnits(c.ctx, contextID, raw)
			return nil
		})
		return out, err
	})

	r.register(svc, "SetLongVegetationProjectFields", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationSelectedUnitFieldsRequest](c, 1)
		if err != nil {
			return nil, err
		}
		if req.Fields == nil {
			req.Fields = []string{}
		}
		raw, err := marshalTypedJSON(req)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out *vegreport.LongVegetationReportScope
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).SetLongVegetationProjectFields(c.ctx, contextID, raw)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "SetLongVegetationReportScope", "prefs", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationScopeRequest](c, 1)
		if err != nil {
			return nil, err
		}
		raw, err := marshalTypedJSON(req)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out *vegreport.LongVegetationReportScope
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationReportScopeService(carrier).SetLongVegetationReportScope(c.ctx, contextID, raw)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "GetLongVegetationProjectWorkbookReview", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationProjectWorkbookReadRequest](c, 1)
		if err != nil {
			return nil, err
		}
		raw, err := marshalTypedJSON(req)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		var out *vegreport.LongVegetationProjectWorkbookReview
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			var innerErr error
			out, innerErr = vegreport.NewLongVegetationProjectWorkbookService(carrier).GetReview(c.ctx, contextID, raw)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "ExportReviewedLongVegetationProjectWorkbook", "download", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationProjectWorkbookExportRequest](c, 1)
		if err != nil {
			return nil, err
		}
		return c.withExportSlot(func(ctx context.Context) (*downloadResult, error) {
			lease, err := c.server.pool.AcquireByContextID(ctx, contextID, c.session.Prefs)
			if err != nil {
				return nil, err
			}
			defer lease.Release()

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-long-vegetation-project.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			req.Destination = filePath // Strictly ignore client-supplied destination.
			raw, err := marshalTypedJSON(req)
			if err != nil {
				cleanup()
				return nil, err
			}
			var outcome *vegreport.VegetationWorkbookOutcome
			err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
				var innerErr error
				outcome, innerErr = vegreport.NewLongVegetationProjectWorkbookService(carrier).ExportReviewed(ctx, contextID, raw)
				return innerErr
			})
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "long vegetation project workbook export did not produce a file"
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

	r.register(svc, "GetVegetationWorkbookReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		var out *vegreport.VegetationWorkbookReview
		err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
			wb, innerErr := vegreport.NewVegetationWorkbookService(carrier)
			if innerErr != nil {
				return innerErr
			}
			out, innerErr = wb.GetReview(c.ctx, contextID, requestJSON)
			return innerErr
		})
		return out, err
	})

	r.register(svc, "ExportReviewedVegetationWorkbook", "download", false, func(c *rpcCall) (any, error) {
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

			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-long-vegetation.xlsx")
			filePath, dirPath, cleanup, err := c.server.downloads.MintTempPath(filename)
			if err != nil {
				return nil, err
			}
			rewritten, err := rewriteJSONField(requestJSON, "destination", filePath)
			if err != nil {
				cleanup()
				return nil, err
			}
			var outcome *vegreport.VegetationWorkbookOutcome
			err = c.session.WithScopeCarrier(lease, func(carrier *vprocore.ContextService) error {
				wb, innerErr := vegreport.NewVegetationWorkbookService(carrier)
				if innerErr != nil {
					return innerErr
				}
				outcome, innerErr = wb.ExportReviewed(ctx, contextID, rewritten)
				return innerErr
			})
			if err != nil {
				cleanup()
				return nil, err
			}
			if outcome == nil || outcome.Path == "" {
				cleanup()
				msg := "vegetation workbook export did not produce a file"
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

	// --- Lifeform & Species Attribute Summary ---

	r.register(svc, "PreviewLifeformSummary", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := vegreport.NewLifeformSummaryService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.Preview(c.ctx, contextID)
	})

	r.register(svc, "PreviewLifeformSummaryWithHierarchyBreakpoints", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		policy, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := vegreport.NewLifeformSummaryService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.PreviewWithHierarchyBreakpoints(c.ctx, contextID, policy)
	})

	r.register(svc, "GetLifeformWorkbookReview", "rpc", false, func(c *rpcCall) (any, error) {
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
		s, err := vegreport.NewLifeformWorkbookService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.GetReview(c.ctx, contextID, requestJSON)
	})

	r.register(svc, "ExportReviewedLifeformWorkbook", "download", false, func(c *rpcCall) (any, error) {
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

			s, err := vegreport.NewLifeformWorkbookService(lease.Context)
			if err != nil {
				return nil, err
			}
			filename := sanitizeDownloadFilename(lease.Dataset.Project + "-lifeform-summary.xlsx")
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
				msg := "lifeform workbook export did not produce a file"
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

	r.register(svc, "PreviewSpeciesAttributeSummary", "rpc", true, func(c *rpcCall) (any, error) {
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
		s, err := vegreport.NewSpeciesAttributeSummaryService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.Preview(c.ctx, contextID)
	})

	r.register(svc, "PreviewSpeciesAttributeSummaryWithHierarchyBreakpoints", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		policy, err := decodeArg[string](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := vegreport.NewSpeciesAttributeSummaryService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.PreviewWithHierarchyBreakpoints(c.ctx, contextID, policy)
	})

	// --- SiteUnit Exclusion Filters & Dynamic Hierarchy Breakpoint (~) ---

	r.register(svc, "GetDefaultSiteUnitExclusions", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(0); err != nil {
			return nil, err
		}
		return vegreport.DefaultSiteUnitExclusionPatterns(), nil
	})

	r.register(svc, "PreviewSiteUnitExclusions", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.SiteUnitExclusionPreviewRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return vegreport.PreviewSiteUnitExclusions(c.ctx, lease.Context, contextID, req)
	})

	r.register(svc, "ResolveHierarchyBreakpointUnits", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.HierarchyBreakpointRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return vegreport.ResolveHierarchyBreakpointUnits(c.ctx, lease.Context, contextID, req)
	})

	r.register(svc, "PreviewSummaryVegetationWithExclusions", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.SummaryVegetationExclusionRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return vegreport.PreviewSummaryVegetationWithExclusions(c.ctx, lease.Context, contextID, req)
	})

	r.register(svc, "PreviewLongVegetationWithExclusions", "rpc", true, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.LongVegetationExclusionRequest](c, 1)
		if err != nil {
			return nil, err
		}
		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return vegreport.PreviewLongVegetationWithExclusions(c.ctx, lease.Context, contextID, req)
	})

	// --- Read-Only Quarto-Style HTML Reports ---

	r.register(svc, "RenderSummaryVegetationHTMLReport", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.QuickSummaryVegetationRequest](c, 1)
		if err != nil {
			return nil, err
		}
		// Pure read-only HTML render: never persist preferences, write disk paths, or launch desktop apps.
		savePrefs := false
		req.SavePreferences = &savePrefs
		req.DestinationPath = ""
		req.OpenInSpreadsheet = false

		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		s, err := vegreport.NewSummaryVegetationService(lease.Context)
		if err != nil {
			return nil, err
		}
		return s.RenderHTMLReport(c.ctx, contextID, req)
	})

	r.register(svc, "RenderLongVegetationHTMLReport", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.QuickLongVegetationRequest](c, 1)
		if err != nil {
			return nil, err
		}
		// Pure read-only HTML render: never persist preferences, write disk paths, or launch desktop apps.
		savePrefs := false
		req.SavePreferences = &savePrefs
		req.DestinationPath = ""
		req.OpenInSpreadsheet = false

		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return vegreport.RenderLongVegetationHTMLReport(lease.Context, c.ctx, contextID, req)
	})

	r.register(svc, "RenderLifeformHTMLReport", "rpc", false, func(c *rpcCall) (any, error) {
		if err := c.requireArgCount(2); err != nil {
			return nil, err
		}
		contextID, err := decodeArg[string](c, 0)
		if err != nil {
			return nil, err
		}
		req, err := decodeArg[vegreport.QuickLifeformReportRequest](c, 1)
		if err != nil {
			return nil, err
		}
		req.DestinationPath = ""
		req.OpenInSpreadsheet = false

		lease, err := c.acquireByContextID(contextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()
		return vegreport.RenderLifeformHTMLReport(lease.Context, c.ctx, contextID, req)
	})
}
