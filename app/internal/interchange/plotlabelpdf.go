package interchange

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"

	"codeberg.org/go-pdf/fpdf"
	"golang.org/x/image/font/sfnt"
	"golang.org/x/text/unicode/norm"
)

// Private portable preparation, not Access printer geometry or an export API.
type plotLabelPDFFonts struct {
	regular, bold         []byte
	regularName, boldName string
}

type plotLabelPDFField struct {
	name, text         string
	left, top, width   float64
	size, lineStep     float64
	maxLines           int
	bold, rightAligned bool
}

func plotLabelPDFFields(preview PlotLabelRegionalPreview) ([]plotLabelPDFField, time.Time, error) {
	if preview.ContextID == "" || preview.PlotNumber == "" || preview.PlotNumber != preview.Header.PlotNumber {
		return nil, time.Time{}, errors.New("label PDF requires a complete matching saved-plot owner")
	}
	h := preview.Header
	for _, item := range []struct {
		name  string
		value *string
		limit int
	}{
		{"PlotNumber1", &h.PlotNumber, 7}, {"Zone", h.Zone, 4}, {"SubZone", h.SubZone, 50},
		{"SiteSeries", h.SiteSeries, 50}, {"Representing1", h.PlotRepresenting, 255}, {"ProjectID1", h.ProjectID, 50},
	} {
		if item.value != nil {
			if err := plotLabelText(*item.value, item.name, item.limit); err != nil {
				return nil, time.Time{}, err
			}
		}
	}
	value := func(text *string) string {
		if text == nil {
			return ""
		}
		return *text
	}
	zoneRaw := value(h.Zone)
	pad := 4 - len(utf16.Encode([]rune(zoneRaw)))
	if pad < 0 {
		pad = 0
	}
	zone := zoneRaw + strings.Repeat(" ", pad) + value(h.SubZone) + "/" + value(h.SiteSeries)
	if err := plotLabelText(zone, "Zone1", 50); err != nil {
		return nil, time.Time{}, err
	}
	date, err := time.Parse("2006-01-02", preview.ISODate)
	if err != nil || date.Year() < 1601 || date.Year() > 9999 {
		return nil, time.Time{}, errors.Join(err, errors.New("label PDF requires a supported complete ISO date"))
	}
	if preview.Source != "windows-user-long-date" ||
		!utf8.ValidString(preview.Locale) || strings.TrimSpace(preview.Locale) == "" ||
		!utf8.ValidString(preview.Pattern) || strings.TrimSpace(preview.Pattern) == "" ||
		!utf8.ValidString(preview.LabelDate) || strings.TrimSpace(preview.LabelDate) == "" {
		return nil, time.Time{}, errors.New("label PDF requires a valid Windows Long Date preview")
	}
	if preview.Locale == "en-US" && preview.Pattern == "dddd, MMMM d, yyyy" &&
		preview.LabelDate != date.Format("Monday, January 2, 2006") {
		return nil, time.Time{}, errors.New("label PDF requires a matching Windows Long Date for its ISO date")
	}
	fields := []plotLabelPDFField{
		{name: "PlotNumber1", text: strings.Trim(h.PlotNumber, " "), left: 72, top: 60, width: 1213, size: 9, lineStep: 9, maxLines: 1, bold: true, rightAligned: false},
		{name: "Representing1", text: strings.Trim(value(h.PlotRepresenting), " "), left: 72, top: 300, width: 4753, size: 6, lineStep: 6, maxLines: 3, bold: false, rightAligned: false},
		{name: "Zone1", text: zone, left: 2448, top: 60, width: 2385, size: 9, lineStep: 9, maxLines: 1, bold: true, rightAligned: true},
		{name: "Date", text: "Label Date: " + preview.LabelDate, left: 507, top: 660, width: 4320, size: 6, lineStep: 6, maxLines: 1, bold: false, rightAligned: true},
		{name: "ProjectID1", text: value(h.ProjectID), left: 1296, top: 60, width: 1155, size: 8, lineStep: 8, maxLines: 1, bold: true, rightAligned: false},
		{name: "RK", text: "(VPro)", left: 75, top: 660, width: 420, size: 6, lineStep: 6, maxLines: 1, bold: false, rightAligned: false},
	}
	for _, field := range fields {
		for _, r := range field.text {
			if !utf8.ValidRune(r) || r == 127 || (r < 32 && r != '\t' && r != '\n' && r != '\r') {
				return nil, time.Time{}, fmt.Errorf("%s label PDF contains unsupported control or invalid character", field.name)
			}
		}
	}
	return fields, date, nil
}

func validatePlotLabelPDFFont(data []byte, expectedName string) error {
	return validatePlotLabelPDFFontNames(data, expectedName)
}

func validatePlotLabelPDFFontNames(data []byte, allowedNames ...string) error {
	_, err := parseAndValidatePlotLabelPDFFont(data, allowedNames...)
	return err
}

func parseAndValidatePlotLabelPDFFont(data []byte, allowedNames ...string) (*sfnt.Font, error) {
	font, err := sfnt.Parse(data)
	if err != nil {
		return nil, fmt.Errorf("label PDF font parse: %w", err)
	}
	name, err := font.Name(nil, sfnt.NameID(6))
	matched := false
	if err == nil {
		for _, allowed := range allowedNames {
			if allowed != "" && name == allowed {
				matched = true
				break
			}
		}
	}
	if err != nil || !matched {
		expectedLabel := ""
		if len(allowedNames) > 0 {
			expectedLabel = allowedNames[0]
		}
		return nil, errors.Join(err, fmt.Errorf("label PDF requires original %s, not substituted font %q", expectedLabel, name))
	}
	if len(data) < 12 || binary.BigEndian.Uint32(data[:4]) != 0x00010000 {
		return nil, errors.New("label PDF requires TrueType outlines")
	}
	count := int(binary.BigEndian.Uint16(data[4:6]))
	if count > (len(data)-12)/16 {
		return nil, errors.New("label PDF font table directory is incomplete")
	}
	found := false
	for i := 0; i < count; i++ {
		table := data[12+i*16 : 12+(i+1)*16]
		if string(table[:4]) != "OS/2" {
			continue
		}
		if found {
			return nil, errors.New("label PDF font has duplicate embedding metadata")
		}
		found = true
		offset, length := uint64(binary.BigEndian.Uint32(table[8:12])), uint64(binary.BigEndian.Uint32(table[12:16]))
		if length < 10 || offset+length > uint64(len(data)) {
			return nil, errors.New("label PDF font embedding metadata is incomplete")
		}
		flags := binary.BigEndian.Uint16(data[offset+8 : offset+10])
		if flags != 0 && flags != 8 {
			return nil, fmt.Errorf("label PDF font embedding/subsetting permissions are unsupported: 0x%04x", flags)
		}
	}
	if !found {
		return nil, errors.New("label PDF font lacks explicit embedding metadata")
	}
	for r := rune(32); r <= 126; r++ {
		glyph, err := font.GlyphIndex(nil, r)
		if err != nil || glyph == 0 {
			return nil, errors.Join(err, fmt.Errorf("label PDF font lacks required glyph U+%04X", r))
		}
	}
	return font, nil
}

func renderPlotLabelPDF(ctx context.Context, preview PlotLabelRegionalPreview, fonts plotLabelPDFFonts) ([]byte, error) {
	if ctx == nil {
		return nil, errors.New("label PDF requires a context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	fields, date, err := plotLabelPDFFields(preview)
	if err != nil {
		return nil, err
	}
	pdf := fpdf.New("P", "pt", "Letter", "")
	pdf.SetMargins(0, 0, 0)
	pdf.SetAutoPageBreak(false, 0)
	pdf.SetCatalogSort(true)
	pdf.SetCreationDate(date)
	pdf.SetModificationDate(date)
	regNames := []string{"ArialMT", "LiberationSans"}
	if fonts.regularName != "" {
		regNames = []string{fonts.regularName}
	}
	bldNames := []string{"Arial-BoldMT", "LiberationSans-Bold"}
	if fonts.boldName != "" {
		bldNames = []string{fonts.boldName}
	}
	// Go/fpdf formats PDF coordinates with locale-invariant '.' decimals regardless of Windows regional numeric settings.
	parsedFonts := make(map[string]*sfnt.Font, 2)
	for _, font := range []struct {
		data  []byte
		names []string
		style string
	}{
		{fonts.regular, regNames, ""},
		{fonts.bold, bldNames, "B"},
	} {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		data := bytes.Clone(font.data)
		parsed, err := parseAndValidatePlotLabelPDFFont(data, font.names...)
		if err != nil {
			return nil, err
		}
		parsedFonts[font.style] = parsed
		pdf.AddUTF8FontFromBytes("VPROSystemArial", font.style, data)
		// Registration errors in this library become observable at selection.
		pdf.SetFont("VPROSystemArial", font.style, 6)
		if err := pdf.Error(); err != nil {
			return nil, fmt.Errorf("label PDF font registration: %w", err)
		}
	}
	pdf.AddPage()
	for _, field := range fields {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		style := ""
		if field.bold {
			style = "B"
		}
		sf := parsedFonts[style]
		pdf.SetFont("VPROSystemArial", style, field.size)
		if err := pdf.Error(); err != nil {
			return nil, err
		}
		maxLines := field.maxLines
		if maxLines < 1 {
			maxLines = 1
		}
		safeText := normalizePlotLabelPDFTextForFont(field.text, sf, maxLines > 1)
		maxWidth := field.width / 20
		lines := wrapAndClipPlotLabelPDFLines(pdf.GetStringWidth, safeText, maxWidth, maxLines)
		if err := pdf.Error(); err != nil {
			return nil, err
		}
		step := field.lineStep
		if step <= 0 {
			step = field.size
		}
		for i, line := range lines {
			width := pdf.GetStringWidth(line)
			if err := pdf.Error(); err != nil {
				return nil, err
			}
			x := 36 + field.left/20
			if field.rightAligned {
				x += maxWidth - width
			}
			y := 36 + field.top/20 + field.size + float64(i)*step
			pdf.Text(x, y, line)
		}
	}
	var output bytes.Buffer
	if err := pdf.Output(&output); err != nil {
		return nil, fmt.Errorf("label PDF encoding: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return output.Bytes(), nil
}

func plotLabelFontHasBMPRune(sf *sfnt.Font, r rune) bool {
	if sf == nil || r < 32 || r == 127 || r > 0xFFFF {
		return false
	}
	glyph, err := sf.GlyphIndex(nil, r)
	return err == nil && glyph != 0
}

func isPlotLabelIgnorableRune(r rune) bool {
	return r == '\u00AD' ||
		(r >= '\u200B' && r <= '\u200F') ||
		(r >= '\u202A' && r <= '\u202E') ||
		r == '\u2060' ||
		(r >= '\u2066' && r <= '\u2069') ||
		(r >= '\uFE00' && r <= '\uFE0F') ||
		r == '\uFEFF'
}

func plotLabelPDFRuneFallback(r rune) (string, bool) {
	switch r {
	case '\u2014', '\u2015':
		return "--", true
	case '\u2010', '\u2011', '\u2012', '\u2013', '\u2212':
		return "-", true
	case '\u00B1':
		return "+/-", true
	case '\u00B0':
		return " deg", true
	case '\u00D7':
		return "x", true
	case '\u00F7':
		return "/", true
	case '\u2018', '\u2019', '\u201A', '\u2032':
		return "'", true
	case '\u201C', '\u201D', '\u201E', '\u2033':
		return "\"", true
	case '\u2026':
		return "...", true
	case '\u2022', '\u00B7':
		return "*", true
	case '\u2264':
		return "<=", true
	case '\u2265':
		return ">=", true
	case '\u2260':
		return "!=", true
	case '\u2248':
		return "~=", true
	default:
		return "", false
	}
}

// normalizePlotLabelPDFTextForFont preserves native BMP TrueType glyphs when supported by sf
// (including Latin accents, em-dash, degree, plus-minus) and deterministically normalizes or
// transliterates unsupported/non-BMP codepoints (such as CJK or supplementary-plane emoji, which
// fpdf's UCS-2 utf8toutf16 cannot encode directly) into ASCII glyphs present in sf.
func normalizePlotLabelPDFTextForFont(raw string, sf *sfnt.Font, allowNewlines bool) string {
	if raw == "" {
		return ""
	}
	normalized := strings.ReplaceAll(raw, "\r\n", "\n")
	normalized = strings.Map(func(r rune) rune {
		switch r {
		case '\r', '\u2028', '\u2029', '\n':
			if allowNewlines {
				return '\n'
			}
			return ' '
		case '\t':
			return ' '
		default:
			return r
		}
	}, normalized)
	normalized = norm.NFC.String(normalized)

	var out strings.Builder
	out.Grow(len(normalized))
	for _, r := range normalized {
		if r == '\n' && allowNewlines {
			out.WriteByte('\n')
			continue
		}
		if plotLabelFontHasBMPRune(sf, r) {
			out.WriteRune(r)
			continue
		}
		if isPlotLabelIgnorableRune(r) {
			continue
		}
		if unicode.IsSpace(r) {
			out.WriteByte(' ')
			continue
		}
		if repl, ok := plotLabelPDFRuneFallback(r); ok {
			out.WriteString(repl)
			continue
		}
		decomp := norm.NFKD.String(string(r))
		var base []rune
		allSupported := true
		for _, d := range decomp {
			if unicode.Is(unicode.Mn, d) || unicode.Is(unicode.Me, d) || unicode.Is(unicode.Mc, d) || isPlotLabelIgnorableRune(d) {
				continue
			}
			if unicode.IsSpace(d) {
				base = append(base, ' ')
				continue
			}
			if !plotLabelFontHasBMPRune(sf, d) {
				allSupported = false
				break
			}
			base = append(base, d)
		}
		if len(base) > 0 && allSupported {
			out.WriteString(string(base))
			continue
		}
		fmt.Fprintf(&out, "[U+%04X]", r)
	}
	return out.String()
}

func wrapAndClipPlotLabelPDFLines(measure func(string) float64, text string, maxWidth float64, maxLines int) []string {
	if maxLines < 1 {
		maxLines = 1
	}
	if !strings.ContainsRune(text, '\n') && measure(text) <= maxWidth {
		return []string{text}
	}
	if maxLines == 1 {
		single := strings.ReplaceAll(text, "\n", " ")
		if measure(single) <= maxWidth {
			return []string{single}
		}
		return []string{clipPlotLabelPDFLine(measure, single, maxWidth)}
	}
	var wrapped []string
	for _, para := range strings.Split(text, "\n") {
		wrapped = append(wrapped, wrapPlotLabelPDFParagraph(measure, para, maxWidth)...)
	}
	if len(wrapped) == 0 {
		return []string{""}
	}
	if len(wrapped) <= maxLines {
		return wrapped
	}
	result := make([]string, maxLines)
	copy(result, wrapped[:maxLines-1])
	remainder := strings.Join(wrapped[maxLines-1:], " ")
	result[maxLines-1] = clipPlotLabelPDFLine(measure, remainder, maxWidth)
	return result
}

func wrapPlotLabelPDFParagraph(measure func(string) float64, paragraph string, maxWidth float64) []string {
	trimmed := strings.TrimSpace(paragraph)
	if trimmed == "" {
		return nil
	}
	if measure(trimmed) <= maxWidth {
		return []string{trimmed}
	}
	runes := []rune(trimmed)
	var lines []string
	start := 0
	for start < len(runes) {
		for start < len(runes) && runes[start] == ' ' {
			start++
		}
		if start >= len(runes) {
			break
		}
		remaining := string(runes[start:])
		if measure(remaining) <= maxWidth {
			lines = append(lines, strings.TrimRight(remaining, " "))
			break
		}
		lo, hi := 1, len(runes)-start
		fit := 1
		for lo <= hi {
			mid := (lo + hi) / 2
			if measure(string(runes[start:start+mid])) <= maxWidth {
				fit = mid
				lo = mid + 1
			} else {
				hi = mid - 1
			}
		}
		end := start + fit
		nextStart := end
		if end < len(runes) && runes[end] == ' ' {
			nextStart = end + 1
		} else {
			breakIdx := -1
			keepBreakChar := false
			for i := end - 1; i > start; i-- {
				if runes[i] == ' ' {
					breakIdx = i
					keepBreakChar = false
					break
				}
				if runes[i] == '-' || runes[i] == '/' {
					breakIdx = i
					keepBreakChar = true
					break
				}
			}
			if breakIdx > start || (breakIdx == start && keepBreakChar) {
				if keepBreakChar {
					end = breakIdx + 1
					nextStart = breakIdx + 1
				} else {
					end = breakIdx
					nextStart = breakIdx + 1
				}
			}
		}
		line := strings.TrimRight(string(runes[start:end]), " ")
		if line != "" {
			lines = append(lines, line)
		}
		if nextStart <= start {
			nextStart = start + 1
		}
		start = nextStart
	}
	return lines
}

func clipPlotLabelPDFLine(measure func(string) float64, text string, maxWidth float64) string {
	text = strings.TrimSpace(text)
	if measure(text) <= maxWidth {
		return text
	}
	const ellipsis = "..."
	runes := []rune(text)
	if measure(ellipsis) > maxWidth {
		lo, hi, best := 0, len(runes), 0
		for lo <= hi {
			mid := (lo + hi) / 2
			if measure(string(runes[:mid])) <= maxWidth {
				best = mid
				lo = mid + 1
			} else {
				hi = mid - 1
			}
		}
		return string(runes[:best])
	}
	lo, hi, best := 0, len(runes), 0
	for lo <= hi {
		mid := (lo + hi) / 2
		candidate := strings.TrimRight(string(runes[:mid]), " ") + ellipsis
		if measure(candidate) <= maxWidth {
			best = mid
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}
	return strings.TrimRight(string(runes[:best]), " ") + ellipsis
}
