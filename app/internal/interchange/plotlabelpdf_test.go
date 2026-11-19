package interchange

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"codeberg.org/go-pdf/fpdf"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func plotLabelPDFTestPreview() PlotLabelRegionalPreview {
	zone, subzone, site, representing, project := "A", "B", "", "  represented plot 1  ", "ID-1"
	return PlotLabelRegionalPreview{
		ContextID: "owned-context", PlotNumber: "P01",
		Header:    SavedPlotLabelHeader{"P01", &zone, &subzone, &site, &representing, &project},
		LabelDate: "Monday, October 12, 2026", ISODate: "2026-10-12",
		Locale: "en-US", Pattern: "dddd, MMMM d, yyyy", Source: "windows-user-long-date",
	}
}

func TestPlotLabelPDFSourceProjection(t *testing.T) {
	preview := plotLabelPDFTestPreview()
	before, err := json.Marshal(preview)
	if err != nil {
		t.Fatal(err)
	}
	fields, date, err := plotLabelPDFFields(preview)
	if err != nil {
		t.Fatal(err)
	}
	var actual []string
	for _, field := range fields {
		actual = append(actual, field.text)
	}
	expected := []string{"P01", "represented plot 1", "A   B/", "Label Date: Monday, October 12, 2026", "ID-1", "(VPro)"}
	if !reflect.DeepEqual(actual, expected) || date.Format("2006-01-02") != "2026-10-12" {
		t.Fatalf("unexpected projection: %v, %v", actual, date)
	}
	after, err := json.Marshal(preview)
	if err != nil || string(before) != string(after) {
		t.Fatalf("source changed: %s -> %s, %v", before, after, err)
	}
}

func TestPlotLabelPDFNullEmptyAndLiteralSpaces(t *testing.T) {
	for _, empty := range []bool{false, true} {
		preview := plotLabelPDFTestPreview()
		preview.Header.PlotRepresenting, preview.Header.ProjectID = nil, nil
		if empty {
			value := ""
			preview.Header.PlotRepresenting, preview.Header.ProjectID = &value, &value
		}
		fields, _, err := plotLabelPDFFields(preview)
		if err != nil || fields[1].text != "" || fields[4].text != "" {
			t.Fatalf("blank metadata: %v, %v", fields, err)
		}
		if (preview.Header.ProjectID == nil) == empty {
			t.Fatal("NULL/empty source distinction lost")
		}
	}
	preview := plotLabelPDFTestPreview()
	preview.PlotNumber, preview.Header.PlotNumber = " P01 ", " P01 "
	project := " ID-1 "
	preview.Header.ProjectID = &project
	fields, _, err := plotLabelPDFFields(preview)
	if err != nil || fields[0].text != "P01" || fields[4].text != " ID-1 " {
		t.Fatalf("literal display: %v, %v", fields, err)
	}
}

func TestPlotLabelPDFSourceDateCases(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("testdata", "plot-label-regional-date.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Cases []struct{ ISODate, Actual string }
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	if len(fixture.Cases) != 12 {
		t.Fatalf("source cases: %d", len(fixture.Cases))
	}
	for _, source := range fixture.Cases {
		preview := plotLabelPDFTestPreview()
		preview.ISODate, preview.LabelDate = source.ISODate, strings.TrimPrefix(source.Actual, "Label Date: ")
		fields, _, err := plotLabelPDFFields(preview)
		if err != nil || fields[3].text != source.Actual {
			t.Fatalf("%s: %v, %v", source.ISODate, fields, err)
		}
	}
}

func TestPlotLabelPDFRefusesUnsupportedProjection(t *testing.T) {
	cases := []struct {
		name, want string
		fonts      plotLabelPDFFonts
		change     func(*PlotLabelRegionalPreview)
	}{
		{"owner", "matching saved-plot owner", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.ContextID = "" }},
		{"identity", "matching saved-plot owner", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.Header.PlotNumber = "P02" }},
		{"long-zone", "UTF-16 bound", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { s := "ABCDE"; p.Header.Zone = &s }},
		{"long-project", "UTF-16 bound", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { s := strings.Repeat("x", 51); p.Header.ProjectID = &s }},
		{"combined-zone", "Zone1", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { s := strings.Repeat("x", 46); p.Header.SiteSeries = &s }},
		{"invalid-utf8", "repairing source text", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { s := string([]byte{0xff}); p.Header.ProjectID = &s }},
		{"nul", "repairing source text", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { s := "a\x00"; p.Header.PlotRepresenting = &s }},
		{"c0-control", "control", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { s := "a\x01"; p.Header.PlotRepresenting = &s }},
		{"del-control", "control", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { s := "a\x7f"; p.Header.PlotRepresenting = &s }},
		{"date", "ISO date", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.ISODate = "2026-02-30" }},
		{"early-date", "ISO date", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.ISODate = "1600-01-01" }},
		{"date-mismatch", "matching Windows Long Date", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.LabelDate = "Tuesday, October 12, 2026" }},
		{"empty-locale", "valid Windows Long Date", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.Locale = "" }},
		{"empty-pattern", "valid Windows Long Date", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.Pattern = "" }},
		{"source", "valid Windows Long Date", plotLabelPDFFonts{}, func(p *PlotLabelRegionalPreview) { p.Source = "browser" }},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			preview := plotLabelPDFTestPreview()
			test.change(&preview)
			output, err := renderPlotLabelPDF(context.Background(), preview, test.fonts)
			if err == nil || !strings.Contains(err.Error(), test.want) || output != nil {
				t.Fatalf("expected %q and zero output, got %q, %v", test.want, output, err)
			}
		})
	}
}

func TestPlotLabelPDFNullZoneNonUSLocaleAndAccentedGlyphs(t *testing.T) {
	fonts, err := loadBundledPlotLabelPDFFonts(context.Background())
	if err != nil {
		t.Fatalf("loadBundledPlotLabelPDFFonts: %v", err)
	}
	// 1. Nullable Zone must space-pad to 4 spaces before SubZone/SiteSeries
	previewNull := plotLabelPDFTestPreview()
	previewNull.Header.Zone = nil
	fields, _, err := plotLabelPDFFields(previewNull)
	if err != nil {
		t.Fatalf("null Zone failed: %v", err)
	}
	if fields[2].text != "    B/" {
		t.Fatalf("expected 4-space padded Zone1 %q, got %q", "    B/", fields[2].text)
	}
	// 2. Non-en-US Windows locales (en-CA, fr-CA) + Unicode/CP1252 accented text must render validly
	for _, tc := range []struct {
		name, locale, pattern, labelDate, representing string
	}{
		{"en-CA", "en-CA", "MMMM d, yyyy", "October 12, 2026", "Café — Mont-Sainte-Anne"},
		{"fr-CA", "fr-CA", "d MMMM yyyy", "12 octobre 2026", "Forêt boréale protégée"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := previewNull
			p.Locale = tc.locale
			p.Pattern = tc.pattern
			p.LabelDate = tc.labelDate
			rep := tc.representing
			p.Header.PlotRepresenting = &rep
			pdfBytes, rErr := renderPlotLabelPDF(context.Background(), p, fonts)
			if rErr != nil {
				t.Fatalf("renderPlotLabelPDF(%s) failed: %v", tc.name, rErr)
			}
			if !strings.HasPrefix(string(pdfBytes), "%PDF-1.") || len(pdfBytes) < 512 {
				t.Fatalf("invalid PDF bytes for %s: len=%d", tc.name, len(pdfBytes))
			}
		})
	}
}

func TestPlotLabelPDFContextAndMissingFonts(t *testing.T) {
	preview := plotLabelPDFTestPreview()
	if output, err := renderPlotLabelPDF(nil, preview, plotLabelPDFFonts{}); err == nil || output != nil {
		t.Fatalf("nil context: %q, %v", output, err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if output, err := renderPlotLabelPDF(ctx, preview, plotLabelPDFFonts{}); !errors.Is(err, context.Canceled) || output != nil {
		t.Fatalf("cancellation: %q, %v", output, err)
	}
	if output, err := renderPlotLabelPDF(context.Background(), preview, plotLabelPDFFonts{}); err == nil ||
		!strings.Contains(err.Error(), "font parse") || output != nil {
		t.Fatalf("missing fonts: %q, %v", output, err)
	}
}

func TestPlotLabelPDFNativeCrossPlatformFontRender(t *testing.T) {
	fonts, err := loadPlotLabelPDFFonts(context.Background())
	if err != nil {
		t.Skipf("no ArialMT or LiberationSans system fonts installed on host: %v", err)
	}
	preview := plotLabelPDFTestPreview()
	pdfBytes, err := renderPlotLabelPDF(context.Background(), preview, fonts)
	if err != nil {
		t.Fatalf("renderPlotLabelPDF with native system fonts (%s/%s) failed: %v", fonts.regularName, fonts.boldName, err)
	}
	if !strings.HasPrefix(string(pdfBytes), "%PDF-1.") || len(pdfBytes) < 512 {
		t.Fatalf("expected valid PDF bytes, got len=%d", len(pdfBytes))
	}
}

func TestPlotLabelPDFAllSampleDBPlotsReviewAndExport(t *testing.T) {
	contexts, state := vprotest.ContextServiceFixture(t)
	projectDBPath := contexts.Projects.Sqlite.Attachments["project"]
	rawDB, err := sql.Open("sqlite3", projectDBPath)
	if err != nil {
		t.Fatal(err)
	}
	defer rawDB.Close()

	rows, err := rawDB.Query(`SELECT e.PlotNumber, COALESCE(length(e.PlotRepresenting), 0), e.PlotRepresenting
		FROM Sample_Env e INNER JOIN Sample_Admin a
		ON typeof(a.Plot)='text' AND CAST(a.Plot AS BLOB)=CAST(e.PlotNumber AS BLOB)
		WHERE typeof(e.PlotNumber)='text'
		ORDER BY e.PlotNumber COLLATE BINARY`)
	if err != nil {
		t.Fatal(err)
	}
	type samplePlot struct {
		plotNumber   string
		repLen       int
		representing sql.NullString
	}
	var plots []samplePlot
	for rows.Next() {
		var sp samplePlot
		if err := rows.Scan(&sp.plotNumber, &sp.repLen, &sp.representing); err != nil {
			t.Fatal(err)
		}
		plots = append(plots, sp)
	}
	if err := rows.Close(); err != nil {
		t.Fatal(err)
	}
	if len(plots) < 51 {
		t.Fatalf("expected at least 51 Sample.db plots, got %d", len(plots))
	}

	regSvc, err := NewPlotLabelRegionalService(contexts)
	if err != nil {
		t.Fatal(err)
	}
	pdfSvc := NewPlotLabelPDFExportService(contexts)
	outDir := t.TempDir()
	longCount := 0

	for idx, sp := range plots {
		if sp.repLen > 80 {
			longCount++
		}
		regPreview, err := regSvc.GetPreview(context.Background(), state.ContextID, sp.plotNumber)
		if err != nil || regPreview == nil {
			t.Fatalf("GetPreview(%q, len=%d) failed: %v", sp.plotNumber, sp.repLen, err)
		}
		reqBytes, err := json.Marshal(PlotLabelPDFReviewRequest{PlotNumber: sp.plotNumber})
		if err != nil {
			t.Fatal(err)
		}
		review, err := pdfSvc.GetReview(context.Background(), state.ContextID, string(reqBytes))
		if err != nil || review == nil {
			t.Fatalf("GetReview(%q, len=%d) failed: %v", sp.plotNumber, sp.repLen, err)
		}
		if sp.representing.Valid {
			if review.Preview.Header.PlotRepresenting == nil || *review.Preview.Header.PlotRepresenting != sp.representing.String {
				t.Fatalf("GetReview(%q) mutated PlotRepresenting: got %v, want %q", sp.plotNumber, review.Preview.Header.PlotRepresenting, sp.representing.String)
			}
		} else if review.Preview.Header.PlotRepresenting != nil {
			t.Fatalf("GetReview(%q) lost NULL PlotRepresenting: got %q", sp.plotNumber, *review.Preview.Header.PlotRepresenting)
		}

		dest := filepath.Join(outDir, fmt.Sprintf("plot-%02d-%s.pdf", idx, strings.TrimSpace(sp.plotNumber)))
		expBytes, err := json.Marshal(PlotLabelPDFExportRequest{
			PlotNumber:   sp.plotNumber,
			ApprovalHash: review.ApprovalHash,
			Destination:  dest,
			RequestID:    fmt.Sprintf("11111111-2222-4333-8444-%012d", idx+1),
			SessionID:    review.SessionID,
		})
		if err != nil {
			t.Fatal(err)
		}
		outcome, err := pdfSvc.ExportReviewed(context.Background(), state.ContextID, string(expBytes))
		if err != nil || outcome == nil || outcome.Status != "published" {
			t.Fatalf("ExportReviewed(%q, len=%d) failed: outcome=%+v err=%v", sp.plotNumber, sp.repLen, outcome, err)
		}
		written, err := os.ReadFile(dest)
		if err != nil || !bytes.HasPrefix(written, []byte("%PDF-1.")) {
			t.Fatalf("written PDF invalid for %q: %v", sp.plotNumber, err)
		}
		sum := sha256.Sum256(written)
		if hex.EncodeToString(sum[:]) != review.PDFSHA256 || outcome.SHA256 != review.PDFSHA256 {
			t.Fatalf("SHA256 mismatch for %q: file=%x outcome=%s review=%s", sp.plotNumber, sum, outcome.SHA256, review.PDFSHA256)
		}
		if sp.plotNumber == "8529676" {
			if pdftotextPath, lookErr := exec.LookPath("pdftotext"); lookErr == nil {
				extracted, extErr := exec.Command(pdftotextPath, dest, "-").CombinedOutput()
				if extErr != nil {
					t.Fatalf("pdftotext on 8529676 failed: %v (%s)", extErr, string(extracted))
				}
				txt := string(extracted)
				for _, expectedFragment := range []string{"8529676", "BWBSwk2/06", "Picea engelmannii x glauca", "Pyrola chlorantha", "(VPro)"} {
					if !strings.Contains(txt, expectedFragment) {
						t.Fatalf("8529676 PDF text missing %q in %q", expectedFragment, txt)
					}
				}
			}
		}
	}
	if longCount < 5 {
		t.Fatalf("expected >= 5 Sample.db plots with PlotRepresenting > 80 chars, saw %d", longCount)
	}
}

func TestPlotLabelPDFWrappingClippingAndFullUnicode(t *testing.T) {
	fonts, err := loadBundledPlotLabelPDFFonts(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	parsedRegular, err := parseAndValidatePlotLabelPDFFont(fonts.regular, fonts.regularName)
	if err != nil {
		t.Fatal(err)
	}

	// Verify direct line-width & line-count invariants even on MEMO-length (1500-char) and unbroken strings.
	measurer := fpdf.New("P", "pt", "Letter", "")
	measurer.AddUTF8FontFromBytes("VPROSystemArial", "", bytes.Clone(fonts.regular))
	measurer.SetFont("VPROSystemArial", "", 6)
	const maxWidthPt = 4753.0 / 20.0
	for _, raw := range []string{
		strings.Repeat("Picea engelmannii x glauca - Populus balsamifera - Equisetum arvense - ", 22),
		strings.Repeat("W", 600),
		"Line 1: Tsuga heterophylla\r\nLine 2: Thuja plicata\tLine 3: Polystichum munitum\nLine 4: Hylocomium splendens",
		"Unicode mix: Café — 12.5° ± 0.5° 白樺 森林 🌲 😀",
	} {
		safe := normalizePlotLabelPDFTextForFont(raw, parsedRegular, true)
		lines := wrapAndClipPlotLabelPDFLines(measurer.GetStringWidth, safe, maxWidthPt, 3)
		if len(lines) < 1 || len(lines) > 3 {
			t.Fatalf("unexpected wrapped line count %d for %q", len(lines), raw)
		}
		for i, line := range lines {
			if w := measurer.GetStringWidth(line); w > maxWidthPt+1e-6 {
				t.Fatalf("line %d width %.2f exceeds maxWidth %.2f: %q", i, w, maxWidthPt, line)
			}
			for _, r := range line {
				if !plotLabelFontHasBMPRune(parsedRegular, r) {
					t.Fatalf("line %d contains unsupported/non-BMP rune U+%04X: %q", i, r, line)
				}
			}
		}
	}

	// Verify end-to-end review + export with 255-char PlotRepresenting, 50-char metadata, and full Unicode.
	contexts, state := vprotest.ContextServiceFixture(t)
	pdfSvc := NewPlotLabelPDFExportService(contexts)
	regSvc, err := NewPlotLabelRegionalService(contexts)
	if err != nil {
		t.Fatal(err)
	}

	rep255Words := ("Picea engelmannii x glauca - Populus balsamifera - Alnus incana - Equisetum arvense - " +
		"Linnaea borealis - Mertensia paniculata - Epilobium angustifolium - Leymus innovatus - " +
		"Platanthera obtusata - Orthilia secunda - Pyrola chlorantha - Hylocomium splendens")[:255]
	if len(rep255Words) != 255 {
		t.Fatalf("expected 255 bytes, got %d", len(rep255Words))
	}

	cases := []struct {
		plotNumber   string
		zone         string
		subZone      string
		siteSeries   string
		projectID    string
		representing string
	}{
		{
			plotNumber:   "U255WD",
			zone:         "BWBS",
			subZone:      "wk2",
			siteSeries:   "06",
			projectID:    strings.Repeat("PRJ-", 12) + "XY", // 50 chars
			representing: rep255Words,
		},
		{
			plotNumber:   "U255WW",
			zone:         "CWH",
			subZone:      "vm1",
			siteSeries:   strings.Repeat("W", 40),
			projectID:    strings.Repeat("W", 50),
			representing: strings.Repeat("W", 255),
		},
		{
			plotNumber:   "UUNICO",
			zone:         "ICH",
			subZone:      "mw2",
			siteSeries:   "01",
			projectID:    "Québec—±1°🌲",
			representing: "Forêt boréale — Slope 18° ± 2° · Betula platyphylla (白樺 / 森林) · Tsuga 🌲 test\nLine 2\twith tab & NFD Cafe\u0301",
		},
		{
			plotNumber:   "UEMOJI",
			zone:         "ESSF",
			subZone:      "wc4",
			siteSeries:   "01",
			projectID:    "🌲😀🌲",
			representing: strings.Repeat("🌲", 127) + "x", // 255 UTF-16 code units
		},
	}

	outDir := t.TempDir()
	for idx, tc := range cases {
		t.Run(tc.plotNumber, func(t *testing.T) {
			vprotest.MutateContextFixture(t, contexts.Projects.Sqlite.Attachments["project"],
				fmt.Sprintf(`INSERT INTO Sample_Env(PlotNumber,Zone,SubZone,SiteSeries,PlotRepresenting,ProjectID)
					VALUES(%s,%s,%s,%s,%s,%s)`,
					sqlQuoteLiteral(tc.plotNumber),
					sqlQuoteLiteral(tc.zone),
					sqlQuoteLiteral(tc.subZone),
					sqlQuoteLiteral(tc.siteSeries),
					sqlQuoteLiteral(tc.representing),
					sqlQuoteLiteral(tc.projectID),
				))
			vprotest.MutateContextFixture(t, contexts.Projects.Sqlite.Attachments["project"],
				fmt.Sprintf(`INSERT INTO Sample_Admin(Plot) VALUES(%s)`, sqlQuoteLiteral(tc.plotNumber)))

			regPreview, err := regSvc.GetPreview(context.Background(), state.ContextID, tc.plotNumber)
			if err != nil || regPreview == nil {
				t.Fatalf("GetPreview(%s) failed: %v", tc.plotNumber, err)
			}
			if regPreview.Header.PlotRepresenting == nil || *regPreview.Header.PlotRepresenting != tc.representing {
				t.Fatalf("regional preview altered UTF-8 PlotRepresenting: got %v, want %q", regPreview.Header.PlotRepresenting, tc.representing)
			}

			reqJSON, _ := json.Marshal(PlotLabelPDFReviewRequest{PlotNumber: tc.plotNumber})
			review, err := pdfSvc.GetReview(context.Background(), state.ContextID, string(reqJSON))
			if err != nil || review == nil {
				t.Fatalf("GetReview(%s) failed: %v", tc.plotNumber, err)
			}
			if review.Preview.Header.PlotRepresenting == nil || *review.Preview.Header.PlotRepresenting != tc.representing {
				t.Fatalf("PDF review altered HTML preview UTF-8 PlotRepresenting: got %v, want %q", review.Preview.Header.PlotRepresenting, tc.representing)
			}
			if review.Preview.Header.ProjectID == nil || *review.Preview.Header.ProjectID != tc.projectID {
				t.Fatalf("PDF review altered HTML preview UTF-8 ProjectID: got %v, want %q", review.Preview.Header.ProjectID, tc.projectID)
			}

			dest := filepath.Join(outDir, tc.plotNumber+".pdf")
			expJSON, _ := json.Marshal(PlotLabelPDFExportRequest{
				PlotNumber:   tc.plotNumber,
				ApprovalHash: review.ApprovalHash,
				Destination:  dest,
				RequestID:    fmt.Sprintf("22222222-3333-4444-8555-%012d", idx+1),
				SessionID:    review.SessionID,
			})
			outcome, err := pdfSvc.ExportReviewed(context.Background(), state.ContextID, string(expJSON))
			if err != nil || outcome == nil || outcome.Status != "published" {
				t.Fatalf("ExportReviewed(%s) failed: outcome=%+v err=%v", tc.plotNumber, outcome, err)
			}
			pdfBytes, err := os.ReadFile(dest)
			if err != nil || !bytes.HasPrefix(pdfBytes, []byte("%PDF-1.")) || len(pdfBytes) < 512 {
				t.Fatalf("invalid exported PDF for %s: len=%d err=%v", tc.plotNumber, len(pdfBytes), err)
			}
			if tc.plotNumber == "UUNICO" {
				if pdftotextPath, lookErr := exec.LookPath("pdftotext"); lookErr == nil {
					extracted, extErr := exec.Command(pdftotextPath, dest, "-").CombinedOutput()
					if extErr != nil {
						t.Fatalf("pdftotext on UUNICO failed: %v (%s)", extErr, string(extracted))
					}
					txt := string(extracted)
					for _, expectedFragment := range []string{"UUNICO", "Forêt boréale", "18° ± 2°", "[U+767D]", "[U+1F332]", "Café"} {
						if !strings.Contains(txt, expectedFragment) {
							t.Fatalf("UUNICO PDF text missing %q in %q", expectedFragment, txt)
						}
					}
				}
			}
		})
	}
}

func sqlQuoteLiteral(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}
