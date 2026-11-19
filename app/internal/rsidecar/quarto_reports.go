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

type quartoGuidePlotSeries struct {
	plotNums   []string
	elevs      []float64
	slopes     []float64
	aspects    []float64
	bgcCounts  map[string]int
	unitCounts map[string]int
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
	guideType, minConstancy, err := validateQuartoGuideRequest(ctx, contexts, req)
	if err != nil {
		return nil, err
	}

	cfg := effectiveOptions(opts...)
	rscriptBin, _, err := resolveRscriptBinary(cfg)
	if err != nil {
		return nil, fmt.Errorf("R runtime unavailable for Quarto guide generation: %w", err)
	}

	resolvedTargetUnit, err := resolveDefaultSingleUnitTarget(ctx, contexts, contextID, guideType, req)
	if err != nil {
		return nil, err
	}

	climReq := ClimateEdatopicRequest{
		RefPeriod:   req.RefPeriod,
		GroupBy:     "site_unit",
		BGCFilter:   req.BGCFilter,
		UseActiveSU: req.UseActiveSU,
	}
	if guideType == "single_unit" && resolvedTargetUnit != "" {
		climReq.SiteUnitFilter = resolvedTargetUnit
	}
	climRes, err := ComputePlotClimateAndDualEdatopic(ctx, contexts, contextID, climReq, cfg)
	if err != nil {
		return nil, err
	}

	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*QuartoGuideResult, error) {
		return renderAndPublishQuartoGuide(ctx, plots.Projects.Sqlite, contextID, guideType, resolvedTargetUnit, minConstancy, req, climRes, cfg, rscriptBin)
	})
}

func validateQuartoGuideRequest(ctx context.Context, contexts *vprocore.ContextService, req QuartoGuideRequest) (string, float64, error) {
	if ctx == nil {
		return "", 0, errors.New("RenderQuartoGuide requires a non-nil context")
	}
	if err := ctx.Err(); err != nil {
		return "", 0, err
	}
	if contexts == nil {
		return "", 0, errors.New("context service is unavailable")
	}
	guideType := strings.ToLower(strings.TrimSpace(req.GuideType))
	if guideType == "" {
		guideType = "single_unit"
	}
	if guideType != "single_unit" && guideType != "bgc_unit" {
		return "", 0, fmt.Errorf("unsupported guideType %q (expected single_unit or bgc_unit)", req.GuideType)
	}
	if !utf8.ValidString(req.Title) || !utf8.ValidString(req.ConceptNotes) || !utf8.ValidString(req.TargetUnit) || !utf8.ValidString(req.BGCFilter) {
		return "", 0, errors.New("guide text fields must be valid UTF-8")
	}
	if len(utf16.Encode([]rune(req.Title))) > 200 {
		return "", 0, errors.New("guide title cannot exceed 200 characters")
	}
	if len(utf16.Encode([]rune(req.ConceptNotes))) > 16000 {
		return "", 0, errors.New("concept notes cannot exceed 16,000 characters")
	}
	minConstancy := req.MinConstancyPct
	if minConstancy <= 0 {
		minConstancy = 20.0
	} else if minConstancy > 100.0 {
		minConstancy = 100.0
	}
	return guideType, minConstancy, nil
}

func resolveDefaultSingleUnitTarget(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID, guideType string,
	req QuartoGuideRequest,
) (string, error) {
	resolvedTargetUnit := strings.TrimSpace(req.TargetUnit)
	if guideType != "single_unit" || resolvedTargetUnit != "" {
		return resolvedTargetUnit, nil
	}
	resolved, err := vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*string, error) {
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
	if err != nil {
		return "", err
	}
	if resolved != nil {
		return *resolved, nil
	}
	return "", nil
}

func renderAndPublishQuartoGuide(
	ctx context.Context,
	owner *vprocore.SqliteContext,
	contextID, guideType, resolvedTargetUnit string,
	minConstancy float64,
	req QuartoGuideRequest,
	climRes *ClimateEdatopicResult,
	cfg RuntimeOptions,
	rscriptBin string,
) (*QuartoGuideResult, error) {
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

	series := collectQuartoGuidePlotSeries(envPlots)
	vegRows, err := buildQuartoVegSummary(ctx, owner, series.plotNums, req.ApplyLump, minConstancy)
	if err != nil {
		return nil, err
	}

	bgcLabel, targetUnitLabel, title, conceptNotes := resolveQuartoGuideLabels(
		guideType, owner.Selection.Project, len(envPlots), req, series, climRes.RefPeriod,
	)
	payload := buildQuartoGuidePayload(
		guideType, owner.Selection.Project, title, targetUnitLabel, bgcLabel, conceptNotes,
		envPlots, series, vegRows, climRes,
	)

	projectDir := filepath.Dir(owner.Selection.ProjectPath)
	runDir, tmpDir, cleanup, err := openQuartoGuideRunDir(cfg)
	if err != nil {
		return nil, err
	}
	defer cleanup()

	qmdPath, payloadPath, err := stageQuartoGuideInputs(runDir, guideType, payload)
	if err != nil {
		return nil, err
	}

	childEnv := ConfigureChildREnv(buildIsolatedChildEnv(tmpDir), runtime.GOOS, rscriptBin, ResolveBundledPandocDir(cfg))
	quartoBin := resolveQuartoBinary(cfg)

	htmlBytes, rendererUsed, err := executeQuartoOrFallbackHTML(ctx, runDir, qmdPath, payloadPath, quartoBin, rscriptBin, childEnv)
	if err != nil {
		return nil, err
	}

	absHTML, err := resolveQuartoOutputHTMLPath(req.DestinationPath, projectDir, cfg.DataDir, owner.Selection.Project, guideType, targetUnitLabel)
	if err != nil {
		return nil, err
	}
	htmlSize, htmlSHA, err := publishBytesAtomically(absHTML, htmlBytes)
	if err != nil {
		return nil, err
	}

	pdfPath, pdfStatus, err := maybeRenderQuartoPDF(ctx, req.IncludePDF, runDir, qmdPath, absHTML, quartoBin, childEnv)
	if err != nil {
		return nil, err
	}

	preview := string(htmlBytes)
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
}

func collectQuartoGuidePlotSeries(envPlots []scopedEnvPlot) quartoGuidePlotSeries {
	s := quartoGuidePlotSeries{
		plotNums:   make([]string, 0, len(envPlots)),
		bgcCounts:  map[string]int{},
		unitCounts: map[string]int{},
	}
	for _, ep := range envPlots {
		s.plotNums = append(s.plotNums, ep.PlotNumber)
		if ep.Elevation != nil {
			s.elevs = append(s.elevs, *ep.Elevation)
		}
		if ep.Slope != nil {
			s.slopes = append(s.slopes, *ep.Slope)
		}
		if ep.Aspect != nil {
			s.aspects = append(s.aspects, *ep.Aspect)
		}
		if ep.BGC != "" {
			s.bgcCounts[ep.BGC]++
		}
		if ep.SiteUnit != "" {
			s.unitCounts[ep.SiteUnit]++
		}
	}
	return s
}

func pickModalKeyLexicographic(counts map[string]int) string {
	bestKey := ""
	bestCnt := 0
	for k, cnt := range counts {
		if cnt > bestCnt || (cnt == bestCnt && k < bestKey) {
			bestCnt = cnt
			bestKey = k
		}
	}
	return bestKey
}

func resolveQuartoGuideLabels(
	guideType, project string,
	plotCount int,
	req QuartoGuideRequest,
	series quartoGuidePlotSeries,
	refPeriod string,
) (bgcLabel, targetUnitLabel, title, conceptNotes string) {
	bgcLabel = strings.TrimSpace(req.BGCFilter)
	if bgcLabel == "" {
		bgcLabel = pickModalKeyLexicographic(series.bgcCounts)
	}
	if bgcLabel == "" {
		bgcLabel = "All BGC Units"
	}

	targetUnitLabel = strings.TrimSpace(req.TargetUnit)
	if targetUnitLabel == "" {
		if guideType == "bgc_unit" {
			targetUnitLabel = bgcLabel
		} else if modal := pickModalKeyLexicographic(series.unitCounts); modal != "" {
			targetUnitLabel = modal
		} else {
			targetUnitLabel = project
		}
	}

	title = strings.TrimSpace(req.Title)
	if title == "" {
		if guideType == "bgc_unit" {
			title = fmt.Sprintf("%s Biogeoclimatic Unit Synthesis", bgcLabel)
		} else {
			title = fmt.Sprintf("%s — Ecosystem Site Unit Guide", targetUnitLabel)
		}
	}

	conceptNotes = strings.TrimSpace(req.ConceptNotes)
	if conceptNotes == "" {
		conceptNotes = fmt.Sprintf(
			"Synthesized BEC ecosystem description for %s (%s) across %d sampled plots using %s climate normals and Ministry CMD -> aSMR edatopic calibration.",
			targetUnitLabel, bgcLabel, plotCount, refPeriod,
		)
	}
	return bgcLabel, targetUnitLabel, title, conceptNotes
}

func buildQuartoGuidePayload(
	guideType, project, title, targetUnitLabel, bgcLabel, conceptNotes string,
	envPlots []scopedEnvPlot,
	series quartoGuidePlotSeries,
	vegRows []QuartoVegSummaryRow,
	climRes *ClimateEdatopicResult,
) map[string]any {
	var unitBreakdown []map[string]any
	if guideType == "bgc_unit" {
		unitBreakdown = buildBGCGuideUnitBreakdown(envPlots, climRes)
	}
	return map[string]any{
		"guideType":       guideType,
		"title":           title,
		"project":         project,
		"targetUnit":      targetUnitLabel,
		"bgcLabel":        bgcLabel,
		"plotCount":       len(envPlots),
		"generatedAt":     time.Now().UTC().Format("2006-01-02 15:04 UTC"),
		"conceptNotes":    conceptNotes,
		"climateSummary":  summarizeQuartoPlotClimate(climRes.Plots),
		"relativeGrid":    climRes.OverallRelative,
		"actualGrid":      climRes.OverallActual,
		"aspectRose":      computeAspectRose(series.aspects),
		"elevationStats":  computeFiveNumberSummary(series.elevs),
		"slopeStats":      computeFiveNumberSummary(series.slopes),
		"vegetationTable": vegRows,
		"unitBreakdown":   unitBreakdown,
	}
}

func summarizeQuartoPlotClimate(plots []PlotClimateRow) any {
	if len(plots) == 0 {
		return nil
	}
	var matS, mapS, mspS, pasS, cmdS float64
	for _, pr := range plots {
		matS += pr.MAT
		mapS += pr.MAP
		mspS += pr.MSP
		pasS += pr.PAS
		cmdS += pr.CMD
	}
	n := float64(len(plots))
	return map[string]any{
		"meanMat": math.Round((matS/n)*10.0) / 10.0,
		"meanMap": math.Round(mapS / n),
		"meanMsp": math.Round(mspS / n),
		"meanPas": math.Round(pasS / n),
		"meanCmd": math.Round(cmdS / n),
	}
}

func buildBGCGuideUnitBreakdown(envPlots []scopedEnvPlot, climRes *ClimateEdatopicResult) []map[string]any {
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
	out := make([]map[string]any, 0, len(climRes.UnitSummaries))
	for _, us := range climRes.UnitSummaries {
		meanAsmrStr := "—"
		if us.MeanASMR != nil {
			meanAsmrStr = fmt.Sprintf("%.2f", *us.MeanASMR)
		}
		modalEda := us.RelativeGrid.ModalCell
		if modalEda == "" {
			modalEda = "—"
		}
		out = append(out, map[string]any{
			"siteUnit":      us.GroupKey,
			"plotCount":     us.PlotCount,
			"modalEdatope":  modalEda,
			"meanAsmr":      meanAsmrStr,
			"meanElevation": formatMeanFloatsOrDash(elevByUnit[us.GroupKey], "%.0f"),
			"meanCmdSite":   formatMeanFloatsOrDash(cmdSiteByUnit[us.GroupKey], "%.0f mm"),
		})
	}
	return out
}

func formatMeanFloatsOrDash(vals []float64, format string) string {
	if len(vals) == 0 {
		return "—"
	}
	sum := 0.0
	for _, v := range vals {
		sum += v
	}
	return fmt.Sprintf(format, sum/float64(len(vals)))
}

func openQuartoGuideRunDir(cfg RuntimeOptions) (string, string, func(), error) {
	baseWork := strings.TrimSpace(cfg.WorkRootDir)
	if baseWork == "" && strings.TrimSpace(cfg.DataDir) != "" {
		if resolved, err := defaultRWorkRootDir(cfg.DataDir); err == nil {
			baseWork = resolved
		}
	}
	return prepareIsolatedRunDir(baseWork)
}

func stageQuartoGuideInputs(runDir, guideType string, payload map[string]any) (string, string, error) {
	templateName := "single_unit_guide.qmd"
	if guideType == "bgc_unit" {
		templateName = "bgc_unit_guide.qmd"
	}
	qmdPath, err := stageEmbeddedAsset(runDir, templateName)
	if err != nil {
		return "", "", err
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return "", "", err
	}
	payloadPath := filepath.Join(runDir, "guide_payload.json")
	if err := os.WriteFile(payloadPath, payloadBytes, 0600); err != nil {
		return "", "", err
	}
	return qmdPath, payloadPath, nil
}

func executeQuartoOrFallbackHTML(
	ctx context.Context,
	runDir, qmdPath, payloadPath, quartoBin, rscriptBin string,
	childEnv []string,
) ([]byte, string, error) {
	renderedHTMLName := "rendered_guide.html"
	renderedHTMLPath := filepath.Join(runDir, renderedHTMLName)
	rendererUsed := ""

	if quartoBin != "" {
		qCmd := exec.CommandContext(
			ctx, quartoBin, "render", filepath.Base(qmdPath),
			"--to", "html", "-M", "embed-resources:true",
			"-P", "payload_json:guide_payload.json",
			"--output", renderedHTMLName,
		)
		qCmd.Dir = runDir
		qCmd.Env = childEnv
		qCmd.WaitDelay = 2 * time.Second
		var qOut bytes.Buffer
		qCmd.Stdout, qCmd.Stderr = &qOut, &qOut
		if qErr := qCmd.Run(); qErr == nil {
			rendererUsed = "quarto"
		} else if ctxErr := ctx.Err(); ctxErr != nil {
			return nil, "", ctxErr
		}
	}

	if rendererUsed == "" {
		if err := runRMarkdownFallbackHTML(ctx, runDir, qmdPath, payloadPath, renderedHTMLPath, rscriptBin, childEnv); err != nil {
			return nil, "", err
		}
		rendererUsed = "rmarkdown_fallback"
	}

	htmlBytes, err := os.ReadFile(renderedHTMLPath)
	if err != nil || len(htmlBytes) == 0 {
		return nil, "", fmt.Errorf("rendered HTML guide was not produced: %w", err)
	}
	return htmlBytes, rendererUsed, nil
}

func runRMarkdownFallbackHTML(
	ctx context.Context,
	runDir, qmdPath, payloadPath, renderedHTMLPath, rscriptBin string,
	childEnv []string,
) error {
	fallbackScript, err := stageEmbeddedAsset(runDir, "render_guide_fallback.R")
	if err != nil {
		return err
	}
	rCmd := exec.CommandContext(ctx, rscriptBin, "--vanilla", fallbackScript, qmdPath, payloadPath, renderedHTMLPath)
	rCmd.Dir = runDir
	rCmd.Env = childEnv
	rCmd.WaitDelay = 2 * time.Second
	var rOut bytes.Buffer
	rCmd.Stdout, rCmd.Stderr = &rOut, &rOut
	if err := rCmd.Run(); err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ctxErr
		}
		msg := strings.TrimSpace(rOut.String())
		if len(msg) > 600 {
			msg = msg[:600] + "..."
		}
		return fmt.Errorf("Quarto/RMarkdown guide rendering failed (%v): %s", err, msg)
	}
	return nil
}

func resolveQuartoOutputHTMLPath(destPath, projectDir, dataDir, project, guideType, targetUnitLabel string) (string, error) {
	destHTML := strings.TrimSpace(destPath)
	if destHTML == "" {
		slug := sanitizeSlug(project + "_" + guideType + "_" + targetUnitLabel)
		destHTML = resolveDefaultGuideExportPath(projectDir, dataDir, slug+".html")
	} else if !strings.EqualFold(filepath.Ext(destHTML), ".html") {
		destHTML += ".html"
	}
	return filepath.Abs(destHTML)
}

func maybeRenderQuartoPDF(
	ctx context.Context,
	includePDF bool,
	runDir, qmdPath, absHTML, quartoBin string,
	childEnv []string,
) (string, string, error) {
	if !includePDF {
		return "", "", nil
	}
	if quartoBin != "" {
		renderedPDFName := "rendered_guide.pdf"
		renderedPDFPath := filepath.Join(runDir, renderedPDFName)
		pCmd := exec.CommandContext(
			ctx, quartoBin, "render", filepath.Base(qmdPath),
			"--to", "pdf", "-P", "payload_json:guide_payload.json",
			"--output", renderedPDFName,
		)
		pCmd.Dir = runDir
		pCmd.Env = childEnv
		pCmd.WaitDelay = 2 * time.Second
		if pErr := pCmd.Run(); pErr == nil {
			if pdfBytes, readErr := os.ReadFile(renderedPDFPath); readErr == nil && len(pdfBytes) > 0 {
				targetPDF := strings.TrimSuffix(absHTML, filepath.Ext(absHTML)) + ".pdf"
				if _, _, pubErr := publishBytesAtomically(targetPDF, pdfBytes); pubErr == nil {
					return targetPDF, "published", nil
				}
			}
		} else if ctxErr := ctx.Err(); ctxErr != nil {
			return "", "", ctxErr
		}
	}
	return "", "tex_unavailable_print_html_ready", nil
}
