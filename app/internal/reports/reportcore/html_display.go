package reportcore

import (
	"errors"
	"fmt"
	"html"
	"strconv"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// HTMLReportMetadataItem represents one key/value field in the Quarto-style report header.
type HTMLReportMetadataItem struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

// HTMLReportBadge displays a concise summary metric chip (e.g., Units, Plots, Species).
type HTMLReportBadge struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

// HTMLReportRow holds one table row (ordinary data row, section heading divider, or summary total).
type HTMLReportRow struct {
	Cells     []string `json:"cells"`
	IsHeading bool     `json:"isHeading,omitempty"`
	IsSummary bool     `json:"isSummary,omitempty"`
}

// HTMLReportTable represents a single titled data table within a Quarto-style HTML report.
type HTMLReportTable struct {
	Title       string          `json:"title"`
	Subtitle    string          `json:"subtitle,omitempty"`
	PlotCount   int             `json:"plotCount,omitempty"`
	Headers     []string        `json:"headers"`
	NumericCols []bool          `json:"numericCols,omitempty"`
	Rows        []HTMLReportRow `json:"rows"`
	Footnote    string          `json:"footnote,omitempty"`
}

// HTMLReportDocument is the structured input to RenderQuartoHTMLReport.
type HTMLReportDocument struct {
	Title       string                   `json:"title"`
	Subtitle    string                   `json:"subtitle,omitempty"`
	ReportKind  string                   `json:"reportKind"`
	Project     string                   `json:"project"`
	SU          string                   `json:"su"`
	ScopeLabel  string                   `json:"scopeLabel,omitempty"`
	GeneratedAt string                   `json:"generatedAt,omitempty"`
	UnitCount   int                      `json:"unitCount"`
	PlotCount   int                      `json:"plotCount"`
	Metadata    []HTMLReportMetadataItem `json:"metadata,omitempty"`
	Badges      []HTMLReportBadge        `json:"badges,omitempty"`
	Notice      string                   `json:"notice,omitempty"`
	Tables      []HTMLReportTable        `json:"tables"`
	Footnotes   []string                 `json:"footnotes,omitempty"`
}

// HTMLReportResult is the wire payload returned by Render*HTMLReport RPCs.
type HTMLReportResult struct {
	Title      string `json:"title"`
	ReportKind string `json:"reportKind"`
	Project    string `json:"project"`
	SU         string `json:"su"`
	ScopeLabel string `json:"scopeLabel"`
	UnitCount  int    `json:"unitCount"`
	PlotCount  int    `json:"plotCount"`
	TableCount int    `json:"tableCount"`
	Notice     string `json:"notice,omitempty"`
	HTML       string `json:"html"`
}

// FormatMetadataCellText formats a typed SQLite metadata cell for HTML table display.
func FormatMetadataCellText(cell vprocore.ProjectMetadataCell) string {
	switch cell.Storage {
	case "text":
		if cell.Text != nil {
			return *cell.Text
		}
	case "integer":
		if cell.Integer != nil {
			return *cell.Integer
		}
	case "real":
		if cell.Real != nil {
			return strconv.FormatFloat(*cell.Real, 'f', -1, 64)
		}
	}
	return ""
}

// RenderQuartoHTMLReport renders a self-contained, offline-ready, print-friendly
// BC Government Quarto-style HTML report document. All dynamic text is strictly HTML-escaped.
func RenderQuartoHTMLReport(doc HTMLReportDocument) (HTMLReportResult, error) {
	title := strings.TrimSpace(doc.Title)
	if title == "" {
		title = strings.TrimSpace(doc.ReportKind)
	}
	if title == "" {
		return HTMLReportResult{}, errors.New("HTML report requires a title or reportKind")
	}
	generatedAt := strings.TrimSpace(doc.GeneratedAt)
	if generatedAt == "" {
		generatedAt = time.Now().Format("2006-01-02 15:04")
	}
	scopeLabel := strings.TrimSpace(doc.ScopeLabel)
	if scopeLabel == "" {
		if doc.SU != "" && doc.SU != "None" {
			scopeLabel = "Site Unit: " + doc.SU
		} else {
			scopeLabel = "All Project Plots"
		}
	}

	var b strings.Builder
	b.Grow(8192)
	b.WriteString("<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n")
	b.WriteString("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n")
	b.WriteString("<title>")
	b.WriteString(html.EscapeString(title))
	b.WriteString(" — VPro Report</title>\n<style>\n")
	b.WriteString(quartoReportCSS)
	b.WriteString("\n</style>\n</head>\n<body>\n<main class=\"vpro-report\">\n")

	// Header block (BC Gov Navy + Gold accent)
	b.WriteString("  <header class=\"report-header\">\n")
	b.WriteString("    <div class=\"report-kicker\">")
	kicker := "B.C. Ministry of Forests — BEC Program · VPro Report"
	if strings.TrimSpace(doc.ReportKind) != "" {
		kicker = doc.ReportKind + " · VPro"
	}
	b.WriteString(html.EscapeString(kicker))
	b.WriteString("</div>\n")
	b.WriteString("    <h1 class=\"report-title\">")
	b.WriteString(html.EscapeString(title))
	b.WriteString("</h1>\n")
	if strings.TrimSpace(doc.Subtitle) != "" {
		b.WriteString("    <p class=\"report-subtitle\">")
		b.WriteString(html.EscapeString(doc.Subtitle))
		b.WriteString("</p>\n")
	}

	// Metadata grid
	meta := make([]HTMLReportMetadataItem, 0, len(doc.Metadata)+4)
	if strings.TrimSpace(doc.Project) != "" {
		meta = append(meta, HTMLReportMetadataItem{Label: "Project", Value: doc.Project})
	}
	meta = append(meta, HTMLReportMetadataItem{Label: "Scope", Value: scopeLabel})
	if doc.UnitCount > 0 {
		meta = append(meta, HTMLReportMetadataItem{Label: "Units", Value: strconv.Itoa(doc.UnitCount)})
	}
	if doc.PlotCount > 0 {
		meta = append(meta, HTMLReportMetadataItem{Label: "Plots", Value: strconv.Itoa(doc.PlotCount)})
	}
	meta = append(meta, HTMLReportMetadataItem{Label: "Generated", Value: generatedAt})
	meta = append(meta, doc.Metadata...)

	b.WriteString("    <dl class=\"meta-grid\">\n")
	for _, m := range meta {
		if strings.TrimSpace(m.Label) == "" {
			continue
		}
		b.WriteString("      <div class=\"meta-item\"><dt>")
		b.WriteString(html.EscapeString(m.Label))
		b.WriteString("</dt><dd>")
		b.WriteString(html.EscapeString(m.Value))
		b.WriteString("</dd></div>\n")
	}
	b.WriteString("    </dl>\n")

	if len(doc.Badges) > 0 {
		b.WriteString("    <div class=\"badge-row\">\n")
		for _, badge := range doc.Badges {
			b.WriteString("      <span class=\"badge\"><strong>")
			b.WriteString(html.EscapeString(badge.Label))
			b.WriteString(":</strong> ")
			b.WriteString(html.EscapeString(badge.Value))
			b.WriteString("</span>\n")
		}
		b.WriteString("    </div>\n")
	}
	b.WriteString("  </header>\n")

	if strings.TrimSpace(doc.Notice) != "" {
		b.WriteString("  <aside class=\"report-notice\" role=\"note\">")
		b.WriteString(html.EscapeString(doc.Notice))
		b.WriteString("</aside>\n")
	}

	if len(doc.Tables) == 0 {
		b.WriteString("  <section class=\"empty-state\"><p>No matching report rows were found for the active scope and filters.</p></section>\n")
	}

	for idx, tbl := range doc.Tables {
		b.WriteString("  <section class=\"report-section\"")
		if idx > 0 {
			b.WriteString(" data-section-index=\"")
			b.WriteString(strconv.Itoa(idx))
			b.WriteString("\"")
		}
		b.WriteString(">\n")
		if strings.TrimSpace(tbl.Title) != "" || tbl.PlotCount > 0 {
			b.WriteString("    <div class=\"section-heading\">\n")
			b.WriteString("      <h2>")
			b.WriteString(html.EscapeString(tbl.Title))
			b.WriteString("</h2>\n")
			if tbl.PlotCount > 0 {
				b.WriteString(fmt.Sprintf("      <span class=\"plot-pill\">n = %d</span>\n", tbl.PlotCount))
			}
			b.WriteString("    </div>\n")
		}
		if strings.TrimSpace(tbl.Subtitle) != "" {
			b.WriteString("    <p class=\"section-subtitle\">")
			b.WriteString(html.EscapeString(tbl.Subtitle))
			b.WriteString("</p>\n")
		}

		b.WriteString("    <div class=\"table-wrap\">\n      <table class=\"quarto-table\">\n")
		colCount := len(tbl.Headers)
		if colCount > 0 {
			b.WriteString("        <thead>\n          <tr>\n")
			for cIdx, h := range tbl.Headers {
				cls := ""
				if cIdx < len(tbl.NumericCols) && tbl.NumericCols[cIdx] {
					cls = ` class="num"`
				}
				b.WriteString("            <th scope=\"col\"" + cls + ">")
				b.WriteString(html.EscapeString(h))
				b.WriteString("</th>\n")
			}
			b.WriteString("          </tr>\n        </thead>\n")
		}
		b.WriteString("        <tbody>\n")
		if len(tbl.Rows) == 0 {
			span := max(colCount, 1)
			b.WriteString(fmt.Sprintf("          <tr><td colspan=\"%d\" class=\"empty-cell\">No rows in this section.</td></tr>\n", span))
		} else {
			for _, row := range tbl.Rows {
				if row.IsHeading {
					span := max(colCount, max(len(row.Cells), 1))
					headingText := ""
					if len(row.Cells) > 0 {
						headingText = row.Cells[0]
					}
					b.WriteString(fmt.Sprintf("          <tr class=\"group-row\"><th colspan=\"%d\" scope=\"rowgroup\">%s</th></tr>\n",
						span, html.EscapeString(headingText)))
					continue
				}
				rowClass := ""
				if row.IsSummary {
					rowClass = ` class="summary-row"`
				}
				b.WriteString("          <tr" + rowClass + ">")
				cells := row.Cells
				if colCount > len(cells) {
					padded := make([]string, colCount)
					copy(padded, cells)
					cells = padded
				}
				for cIdx, val := range cells {
					cls := ""
					if cIdx < len(tbl.NumericCols) && tbl.NumericCols[cIdx] {
						cls = ` class="num"`
					}
					b.WriteString("<td" + cls + ">")
					b.WriteString(html.EscapeString(val))
					b.WriteString("</td>")
				}
				b.WriteString("</tr>\n")
			}
		}
		b.WriteString("        </tbody>\n      </table>\n    </div>\n")
		if strings.TrimSpace(tbl.Footnote) != "" {
			b.WriteString("    <p class=\"table-footnote\">")
			b.WriteString(html.EscapeString(tbl.Footnote))
			b.WriteString("</p>\n")
		}
		b.WriteString("  </section>\n")
	}

	if len(doc.Footnotes) > 0 {
		b.WriteString("  <footer class=\"report-footer\">\n    <ul>\n")
		for _, note := range doc.Footnotes {
			if strings.TrimSpace(note) == "" {
				continue
			}
			b.WriteString("      <li>")
			b.WriteString(html.EscapeString(note))
			b.WriteString("</li>\n")
		}
		b.WriteString("    </ul>\n  </footer>\n")
	}

	b.WriteString("</main>\n</body>\n</html>\n")

	return HTMLReportResult{
		Title:      title,
		ReportKind: doc.ReportKind,
		Project:    doc.Project,
		SU:         doc.SU,
		ScopeLabel: scopeLabel,
		UnitCount:  doc.UnitCount,
		PlotCount:  doc.PlotCount,
		TableCount: len(doc.Tables),
		Notice:     doc.Notice,
		HTML:       b.String(),
	}, nil
}

const quartoReportCSS = `:root {
  --bc-navy: #003366;
  --bc-navy-light: #1a4f85;
  --bc-gold: #fcba19;
  --ink: #1f2933;
  --ink-muted: #52606d;
  --surface: #ffffff;
  --surface-alt: #f7f9fc;
  --border: #d9e2ec;
  --notice-bg: #fff8e6;
  --notice-border: #d99b00;
}
* { box-sizing: border-box; }
html, body {
  margin: 0;
  padding: 0;
  background: var(--surface);
  color: var(--ink);
  font-family: "BC Sans", "Noto Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  font-size: 13px;
  line-height: 1.45;
}
.vpro-report {
  max-width: 1280px;
  margin: 0 auto;
  padding: 20px 24px 36px;
}
.report-header {
  border-top: 4px solid var(--bc-navy);
  border-bottom: 2px solid var(--bc-gold);
  padding: 14px 0 12px;
  margin-bottom: 18px;
}
.report-kicker {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--bc-navy-light);
  margin-bottom: 4px;
}
.report-title {
  margin: 0;
  font-size: 22px;
  font-weight: 700;
  color: var(--bc-navy);
  line-height: 1.2;
}
.report-subtitle {
  margin: 4px 0 0;
  color: var(--ink-muted);
  font-size: 13px;
}
.meta-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 20px;
  margin: 12px 0 0;
  padding: 0;
}
.meta-item {
  display: flex;
  gap: 6px;
  align-items: baseline;
}
.meta-item dt {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--ink-muted);
}
.meta-item dd {
  margin: 0;
  font-weight: 600;
  color: var(--ink);
}
.badge-row {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 10px;
}
.badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--surface-alt);
  border: 1px solid var(--border);
  font-size: 11px;
  color: var(--bc-navy);
}
.report-notice {
  margin: 0 0 16px;
  padding: 10px 14px;
  background: var(--notice-bg);
  border-left: 4px solid var(--notice-border);
  border-radius: 3px;
  color: #4a3500;
  font-size: 12.5px;
}
.report-section {
  margin-bottom: 24px;
}
.section-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 6px;
}
.section-heading h2 {
  margin: 0;
  font-size: 15px;
  font-weight: 700;
  color: var(--bc-navy);
}
.section-subtitle {
  margin: 0 0 8px;
  color: var(--ink-muted);
  font-size: 12px;
}
.plot-pill {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 10px;
  background: #e6eff8;
  color: var(--bc-navy);
  white-space: nowrap;
}
.table-wrap {
  width: 100%;
  overflow-x: auto;
  border: 1px solid var(--border);
  border-radius: 4px;
}
.quarto-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
  background: var(--surface);
}
.quarto-table thead th {
  position: sticky;
  top: 0;
  background: var(--bc-navy);
  color: #ffffff;
  font-weight: 600;
  text-align: left;
  padding: 7px 9px;
  border-bottom: 2px solid var(--bc-gold);
  white-space: nowrap;
}
.quarto-table tbody td {
  padding: 5px 9px;
  border-bottom: 1px solid #e8eef5;
  vertical-align: top;
}
.quarto-table tbody tr:nth-child(even):not(.group-row):not(.summary-row) {
  background: var(--surface-alt);
}
.quarto-table th.num,
.quarto-table td.num {
  text-align: right;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.quarto-table tr.group-row th {
  background: #edf3f9;
  color: var(--bc-navy);
  font-weight: 700;
  text-align: left;
  padding: 6px 9px;
  letter-spacing: 0.03em;
  border-top: 1px solid var(--border);
  border-bottom: 1px solid var(--border);
}
.quarto-table tr.summary-row td {
  font-weight: 700;
  background: #f0f4f8;
  border-top: 1.5px solid var(--bc-navy);
}
.empty-cell, .empty-state {
  color: var(--ink-muted);
  font-style: italic;
  padding: 14px;
  text-align: center;
}
.table-footnote {
  margin: 6px 0 0;
  font-size: 11px;
  color: var(--ink-muted);
}
.report-footer {
  margin-top: 20px;
  padding-top: 10px;
  border-top: 1px solid var(--border);
  font-size: 11px;
  color: var(--ink-muted);
}
.report-footer ul {
  margin: 0;
  padding-left: 18px;
}
@media print {
  @page { size: landscape; margin: 12mm; }
  html, body { font-size: 10pt; background: #fff; color: #000; }
  .vpro-report { max-width: none; padding: 0; }
  .table-wrap { overflow: visible; border: none; }
  .quarto-table thead { display: table-header-group; }
  .quarto-table thead th {
    position: static;
    background: #003366 !important;
    color: #fff !important;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  .quarto-table tr { break-inside: avoid; }
  .report-section { break-inside: auto; }
  .section-heading { break-after: avoid; }
}`
