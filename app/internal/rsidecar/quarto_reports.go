package rsidecar

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// QuartoVegSummaryRow represents one formatted species row in a published BEC unit/BGC guide.
type QuartoVegSummaryRow struct {
	Layer          string  `json:"layer"`
	Species        string  `json:"species"`
	ScientificName string  `json:"scientificName"`
	EnglishName    string  `json:"englishName"`
	ConstancyPct   float64 `json:"constancyPct"`
	ConstancyClass string  `json:"constancyClass"`
	MeanCover      float64 `json:"meanCover"`
}

// AspectRoseSector holds plot count for one of the 8 cardinal/intercardinal compass octants.
type AspectRoseSector struct {
	Sector string `json:"sector"`
	Count  int    `json:"count"`
}

// FiveNumberBoxSummary holds five-number summary statistics for SVG boxplot rendering.
type FiveNumberBoxSummary struct {
	N      int     `json:"n"`
	Min    float64 `json:"min"`
	Q1     float64 `json:"q1"`
	Median float64 `json:"median"`
	Q3     float64 `json:"q3"`
	Max    float64 `json:"max"`
}

// QuartoGuideRequest configures single-command Quarto BEC unit or BGC subzone HTML/PDF guide publication.
type QuartoGuideRequest struct {
	GuideType       string  `json:"guideType"`       // "single_unit" (default) | "bgc_unit"
	Title           string  `json:"title"`           // Optional custom guide title
	TargetUnit      string  `json:"targetUnit"`      // Optional SiteUnit filter (for single_unit)
	BGCFilter       string  `json:"bgcFilter"`       // Optional BGC filter (for bgc_unit or single_unit)
	ConceptNotes    string  `json:"conceptNotes"`    // Authored ecological concept markdown/notes
	RefPeriod       string  `json:"refPeriod"`       // Climate reference period ("1961_1990" | "1991_2020")
	MinConstancyPct float64 `json:"minConstancyPct"` // Minimum species constancy % threshold (default 20%)
	UseActiveSU     bool    `json:"useActiveSu"`
	ApplyLump       bool    `json:"applyLump"`
	IncludePDF      bool    `json:"includePdf"`
	DestinationPath string  `json:"destinationPath"` // Target .html path (optional; defaults to <ProjectDir>/exports/<slug>.html)
}

func (r *QuartoGuideRequest) UnmarshalJSON(data []byte) error {
	type plain QuartoGuideRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// QuartoGuideResult reports the atomically published HTML/PDF guide artifacts and summary preview.
type QuartoGuideResult struct {
	ContextID       string                `json:"contextId"`
	GuideType       string                `json:"guideType"`
	Title           string                `json:"title"`
	TargetUnit      string                `json:"targetUnit"`
	BGCLabel        string                `json:"bgcLabel"`
	PlotCount       int                   `json:"plotCount"`
	SpeciesRowCount int                   `json:"speciesRowCount"`
	RendererUsed    string                `json:"rendererUsed"` // "quarto" | "rmarkdown_fallback"
	HTMLPath        string                `json:"htmlPath"`
	HTMLSizeBytes   int64                 `json:"htmlSizeBytes"`
	HTMLSHA256      string                `json:"htmlSha256"`
	PDFPath         string                `json:"pdfPath,omitempty"`
	PDFStatus       string                `json:"pdfStatus,omitempty"`
	HTMLPreview     string                `json:"htmlPreview"`
	VegetationTable []QuartoVegSummaryRow `json:"vegetationTable"`
}

// RenderQuartoGuide compiles embedded parameterized Quarto templates (single_unit_guide.qmd or bgc_unit_guide.qmd)
// combining formatted Veg/Env/Climate tables, Dual (rSMR vs aSMR) Edatopic SVG heatmaps, Aspect Rose, and Boxplots,
// and publishes standalone HTML (plus optional PDF) atomically to disk.
func RenderQuartoGuide(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	req QuartoGuideRequest,
	opts ...RuntimeOptions,
) (*QuartoGuideResult, error) {
	if ctx == nil {
		return nil, errors.New("RenderQuartoGuide requires a non-nil context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("context service is unavailable")
	}

	guideType := strings.ToLower(strings.TrimSpace(req.GuideType))
	if guideType == "" {
		guideType = "single_unit"
	}
	if guideType != "single_unit" && guideType != "bgc_unit" {
		return nil, fmt.Errorf("unsupported guideType %q (expected single_unit or bgc_unit)", req.GuideType)
	}
	if !utf8.ValidString(req.Title) || !utf8.ValidString(req.ConceptNotes) || !utf8.ValidString(req.TargetUnit) || !utf8.ValidString(req.BGCFilter) {
		return nil, errors.New("guide text fields must be valid UTF-8")
	}
	if len(utf16.Encode([]rune(req.Title))) > 200 {
		return nil, errors.New("guide title exceeds 200 UTF-16 code units")
	}
	if len(utf16.Encode([]rune(req.ConceptNotes))) > 16000 {
		return nil, errors.New("concept notes exceed 16000 UTF-16 code units")
	}

	minConstancy := req.MinConstancyPct
	if minConstancy <= 0 {
		minConstancy = 20.0
	}
	if minConstancy > 100.0 {
		minConstancy = 100.0
	}

	cfg := effectiveOptions(opts...)
	// Verify Rscript availability upfront for informative error messaging
	rscriptBin, _, rErr := resolveRscriptBinary(cfg)
	if rErr != nil {
		return nil, fmt.Errorf("R runtime unavailable for Quarto guide generation: %w", rErr)
	}

	resolvedTargetUnit := strings.TrimSpace(req.TargetUnit)
	if guideType == "single_unit" && resolvedTargetUnit == "" {
		resolved, rErr := vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*string, error) {
			candidates, cErr := readScopedEnvPlots(ctx, plots.Projects.Sqlite, req.UseActiveSU, req.BGCFilter, "", nil)
			if cErr != nil {
				return nil, cErr
			}
			counts := make(map[string]int)
			best := ""
			bestCnt := 0
			for _, ep := range candidates {
				if ep.SiteUnit == "" {
					continue
				}
				counts[ep.SiteUnit]++
				if counts[ep.SiteUnit] > bestCnt || (counts[ep.SiteUnit] == bestCnt && ep.SiteUnit < best) {
					bestCnt = counts[ep.SiteUnit]
					best = ep.SiteUnit
				}
			}
			return &best, nil
		})
		if rErr != nil {
			return nil, rErr
		}
		if resolved != nil {
			resolvedTargetUnit = *resolved
		}
	}

	// Step 1: Compute/fetch cached __VPRO_PlotClimate & Dual Edatopic Grids for the requested scope
	climReq := ClimateEdatopicRequest{
		RefPeriod:      req.RefPeriod,
		GroupBy:        "site_unit",
		BGCFilter:      req.BGCFilter,
		SiteUnitFilter: "",
		UseActiveSU:    req.UseActiveSU,
	}
	if guideType == "single_unit" && resolvedTargetUnit != "" {
		climReq.SiteUnitFilter = resolvedTargetUnit
	}
	climRes, err := ComputePlotClimateAndDualEdatopic(ctx, contexts, contextID, climReq, cfg)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*QuartoGuideResult, error) {
		owner := plots.Projects.Sqlite
		unitFilter := ""
		if guideType == "single_unit" {
			unitFilter = resolvedTargetUnit
		}
		envPlots, err := readScopedEnvPlots(ctx, owner, req.UseActiveSU, req.BGCFilter, unitFilter, nil)
		if err != nil {
			return nil, err
		}
		if len(envPlots) == 0 {
			return nil, errors.New("no plots matched the requested Quarto guide filter")
		}

		plotNums := make([]string, 0, len(envPlots))
		var elevs, slopes, aspects []float64
		bgcCounts := make(map[string]int)
		unitCounts := make(map[string]int)
		for _, ep := range envPlots {
			plotNums = append(plotNums, ep.PlotNumber)
			if ep.Elevation != nil {
				elevs = append(elevs, *ep.Elevation)
			}
			if ep.Slope != nil {
				slopes = append(slopes, *ep.Slope)
			}
			if ep.Aspect != nil {
				aspects = append(aspects, *ep.Aspect)
			}
			if ep.BGC != "" {
				bgcCounts[ep.BGC]++
			}
			if ep.SiteUnit != "" {
				unitCounts[ep.SiteUnit]++
			}
		}

		vegRows, err := buildQuartoVegSummary(ctx, owner, plotNums, req.ApplyLump, minConstancy)
		if err != nil {
			return nil, err
		}

		// Determine modal BGC & TargetUnit labels
		bgcLabel := strings.TrimSpace(req.BGCFilter)
		if bgcLabel == "" {
			bestCnt := 0
			for b, cnt := range bgcCounts {
				if cnt > bestCnt || (cnt == bestCnt && b < bgcLabel) {
					bestCnt = cnt
					bgcLabel = b
				}
			}
		}
		if bgcLabel == "" {
			bgcLabel = "All BGC Units"
		}

		targetUnitLabel := strings.TrimSpace(req.TargetUnit)
		if targetUnitLabel == "" {
			if guideType == "bgc_unit" {
				targetUnitLabel = bgcLabel
			} else {
				bestCnt := 0
				for u, cnt := range unitCounts {
					if cnt > bestCnt || (cnt == bestCnt && u < targetUnitLabel) {
						bestCnt = cnt
						targetUnitLabel = u
					}
				}
				if targetUnitLabel == "" {
					targetUnitLabel = owner.Selection.Project
				}
			}
		}

		title := strings.TrimSpace(req.Title)
		if title == "" {
			if guideType == "bgc_unit" {
				title = fmt.Sprintf("%s Biogeoclimatic Unit Synthesis", bgcLabel)
			} else {
				title = fmt.Sprintf("%s — Ecosystem Site Unit Guide", targetUnitLabel)
			}
		}
		conceptNotes := strings.TrimSpace(req.ConceptNotes)
		if conceptNotes == "" {
			conceptNotes = fmt.Sprintf(
				"Synthesized BEC ecosystem description for %s (%s) across %d sampled plots using %s climate normals and Ministry CMD -> aSMR edatopic calibration.",
				targetUnitLabel, bgcLabel, len(envPlots), climRes.RefPeriod,
			)
		}

		var climateSummary any
		if len(climRes.Plots) > 0 {
			var matS, mapS, mspS, pasS, cmdS float64
			for _, pr := range climRes.Plots {
				matS += pr.MAT
				mapS += pr.MAP
				mspS += pr.MSP
				pasS += pr.PAS
				cmdS += pr.CMD
			}
			n := float64(len(climRes.Plots))
			climateSummary = map[string]any{
				"meanMat": math.Round((matS/n)*10.0) / 10.0,
				"meanMap": math.Round(mapS / n),
				"meanMsp": math.Round(mspS / n),
				"meanPas": math.Round(pasS / n),
				"meanCmd": math.Round(cmdS / n),
			}
		}

		// Unit breakdown for bgc_unit guide
		var unitBreakdown []map[string]any
		if guideType == "bgc_unit" {
			elevByUnit := make(map[string][]float64)
			for _, ep := range envPlots {
				u := ep.SiteUnit
				if u == "" {
					u = "Unassigned"
				}
				if ep.Elevation != nil {
					elevByUnit[u] = append(elevByUnit[u], *ep.Elevation)
				}
			}
			cmdSiteByUnit := make(map[string][]float64)
			for _, pr := range climRes.Plots {
				u := pr.SiteUnit
				if u == "" {
					u = "Unassigned"
				}
				if pr.CMDSite != nil {
					cmdSiteByUnit[u] = append(cmdSiteByUnit[u], *pr.CMDSite)
				}
			}
			for _, us := range climRes.UnitSummaries {
				meanElevStr := "—"
				if evs := elevByUnit[us.GroupKey]; len(evs) > 0 {
					s := 0.0
					for _, v := range evs {
						s += v
					}
					meanElevStr = fmt.Sprintf("%.0f", s/float64(len(evs)))
				}
				meanAsmrStr := "—"
				if us.MeanASMR != nil {
					meanAsmrStr = fmt.Sprintf("%.2f", *us.MeanASMR)
				}
				meanCmdSiteStr := "—"
				if cs := cmdSiteByUnit[us.GroupKey]; len(cs) > 0 {
					s := 0.0
					for _, v := range cs {
						s += v
					}
					meanCmdSiteStr = fmt.Sprintf("%.0f mm", s/float64(len(cs)))
				}
				modalEda := us.RelativeGrid.ModalCell
				if modalEda == "" {
					modalEda = "—"
				}
				unitBreakdown = append(unitBreakdown, map[string]any{
					"siteUnit":      us.GroupKey,
					"plotCount":     us.PlotCount,
					"modalEdatope":  modalEda,
					"meanAsmr":      meanAsmrStr,
					"meanElevation": meanElevStr,
					"meanCmdSite":   meanCmdSiteStr,
				})
			}
		}

		payload := map[string]any{
			"guideType":       guideType,
			"title":           title,
			"project":         owner.Selection.Project,
			"targetUnit":      targetUnitLabel,
			"bgcLabel":        bgcLabel,
			"plotCount":       len(envPlots),
			"generatedAt":     time.Now().UTC().Format("2006-01-02 15:04 UTC"),
			"conceptNotes":    conceptNotes,
			"climateSummary":  climateSummary,
			"relativeGrid":    climRes.OverallRelative,
			"actualGrid":      climRes.OverallActual,
			"aspectRose":      computeAspectRose(aspects),
			"elevationStats":  computeFiveNumberSummary(elevs),
			"slopeStats":      computeFiveNumberSummary(slopes),
			"vegetationTable": vegRows,
			"unitBreakdown":   unitBreakdown,
		}

		projectDir := filepath.Dir(owner.Selection.ProjectPath)
		baseWork := strings.TrimSpace(cfg.WorkRootDir)
		if baseWork == "" && strings.TrimSpace(cfg.DataDir) != "" {
			if resolved, rErr := defaultRWorkRootDir(cfg.DataDir); rErr == nil {
				baseWork = resolved
			}
		}
		runDir, tmpDir, cleanup, err := prepareIsolatedRunDir(baseWork)
		if err != nil {
			return nil, err
		}
		defer cleanup()

		templateName := "single_unit_guide.qmd"
		if guideType == "bgc_unit" {
			templateName = "bgc_unit_guide.qmd"
		}
		qmdPath, err := stageEmbeddedAsset(runDir, templateName)
		if err != nil {
			return nil, err
		}
		payloadBytes, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		payloadPath := filepath.Join(runDir, "guide_payload.json")
		if err := os.WriteFile(payloadPath, payloadBytes, 0600); err != nil {
			return nil, err
		}

		renderedHTMLName := "rendered_guide.html"
		renderedHTMLPath := filepath.Join(runDir, renderedHTMLName)
		childEnv := ConfigureChildREnv(buildIsolatedChildEnv(tmpDir), runtime.GOOS, rscriptBin, ResolveBundledPandocDir(cfg))

		quartoBin := resolveQuartoBinary(cfg)
		rendererUsed := ""

		if quartoBin != "" {
			qCmd := exec.CommandContext(
				ctx,
				quartoBin,
				"render",
				filepath.Base(qmdPath),
				"--to", "html",
				"-M", "embed-resources:true",
				"-P", "payload_json:guide_payload.json",
				"--output", renderedHTMLName,
			)
			qCmd.Dir = runDir
			qCmd.Env = childEnv
			qCmd.WaitDelay = 2 * time.Second
			var qOut bytes.Buffer
			qCmd.Stdout = &qOut
			qCmd.Stderr = &qOut
			if qErr := qCmd.Run(); qErr == nil {
				rendererUsed = "quarto"
			} else if ctxErr := ctx.Err(); ctxErr != nil {
				return nil, ctxErr
			}
		}

		if rendererUsed == "" {
			fallbackScript, err := stageEmbeddedAsset(runDir, "render_guide_fallback.R")
			if err != nil {
				return nil, err
			}
			rCmd := exec.CommandContext(ctx, rscriptBin, "--vanilla", fallbackScript, qmdPath, payloadPath, renderedHTMLPath)
			rCmd.Dir = runDir
			rCmd.Env = childEnv
			rCmd.WaitDelay = 2 * time.Second
			var rOut bytes.Buffer
			rCmd.Stdout = &rOut
			rCmd.Stderr = &rOut
			if err := rCmd.Run(); err != nil {
				if ctxErr := ctx.Err(); ctxErr != nil {
					return nil, ctxErr
				}
				msg := strings.TrimSpace(rOut.String())
				if len(msg) > 600 {
					msg = msg[:600] + "..."
				}
				return nil, fmt.Errorf("Quarto/RMarkdown guide rendering failed (%v): %s", err, msg)
			}
			rendererUsed = "rmarkdown_fallback"
		}

		htmlBytes, err := os.ReadFile(renderedHTMLPath)
		if err != nil || len(htmlBytes) == 0 {
			return nil, fmt.Errorf("rendered HTML guide was not produced: %w", err)
		}

		destHTML := strings.TrimSpace(req.DestinationPath)
		if destHTML == "" {
			slug := sanitizeSlug(owner.Selection.Project + "_" + guideType + "_" + targetUnitLabel)
			destHTML = resolveDefaultGuideExportPath(projectDir, cfg.DataDir, slug+".html")
		} else if !strings.EqualFold(filepath.Ext(destHTML), ".html") {
			destHTML += ".html"
		}
		absHTML, err := filepath.Abs(destHTML)
		if err != nil {
			return nil, err
		}

		htmlSize, htmlSHA, err := publishBytesAtomically(absHTML, htmlBytes)
		if err != nil {
			return nil, err
		}

		pdfPath := ""
		pdfStatus := ""
		if req.IncludePDF {
			if quartoBin != "" {
				renderedPDFName := "rendered_guide.pdf"
				renderedPDFPath := filepath.Join(runDir, renderedPDFName)
				pCmd := exec.CommandContext(
					ctx,
					quartoBin,
					"render",
					filepath.Base(qmdPath),
					"--to", "pdf",
					"-P", "payload_json:guide_payload.json",
					"--output", renderedPDFName,
				)
				pCmd.Dir = runDir
				pCmd.Env = childEnv
				pCmd.WaitDelay = 2 * time.Second
				if pErr := pCmd.Run(); pErr == nil {
					if pdfBytes, readErr := os.ReadFile(renderedPDFPath); readErr == nil && len(pdfBytes) > 0 {
						targetPDF := strings.TrimSuffix(absHTML, filepath.Ext(absHTML)) + ".pdf"
						if _, _, pubErr := publishBytesAtomically(targetPDF, pdfBytes); pubErr == nil {
							pdfPath = targetPDF
							pdfStatus = "published"
						}
					}
				} else if ctxErr := ctx.Err(); ctxErr != nil {
					return nil, ctxErr
				}
			}
			if pdfPath == "" {
				pdfStatus = "tex_unavailable_print_html_ready"
			}
		}

		preview := string(htmlBytes)
		// Cap inline preview string to 250 KB if extraordinarily large while preserving full standalone HTML for normal guides
		if len(preview) > 256*1024 {
			preview = preview[:256*1024]
		}

		return &QuartoGuideResult{
			ContextID:       contextID,
			GuideType:       guideType,
			Title:           title,
			TargetUnit:      targetUnitLabel,
			BGCLabel:        bgcLabel,
			PlotCount:       len(envPlots),
			SpeciesRowCount: len(vegRows),
			RendererUsed:    rendererUsed,
			HTMLPath:        absHTML,
			HTMLSizeBytes:   htmlSize,
			HTMLSHA256:      htmlSHA,
			PDFPath:         pdfPath,
			PDFStatus:       pdfStatus,
			HTMLPreview:     preview,
			VegetationTable: vegRows,
		}, nil
	})
}
