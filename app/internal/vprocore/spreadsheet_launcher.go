package vprocore

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

// ErrSpreadsheetLaunchUnavailableHeadless is returned by OpenFileInSpreadsheetApp
// when built with -tags vpro_headless (for example, in the read-only web server).
var ErrSpreadsheetLaunchUnavailableHeadless = errors.New("opening files in a desktop spreadsheet application is unavailable in headless mode")

// SpreadsheetAppPreference stores the user's configured external spreadsheet
// application path (blank means the operating system default handler) and
// whether quick report exports should open automatically after creation.
type SpreadsheetAppPreference struct {
	ProgramPath     string `json:"programPath"`
	AutoOpenExports bool   `json:"autoOpenExports"`
}

func (p *SpreadsheetAppPreference) UnmarshalJSON(data []byte) error {
	type plain SpreadsheetAppPreference
	return sqlutil.DecodeStrictJSON(data, (*plain)(p))
}

var allowedSpreadsheetExtensions = map[string]bool{
	".xlsx": true,
	".xlsm": true,
	".xls":  true,
	".ods":  true,
	".csv":  true,
	".tsv":  true,
}

// GetSpreadsheetAppPreference reads the persisted spreadsheet application
// preference from config.yml (System.SpreadsheetProgram and System.AutoOpenReports).
func GetSpreadsheetAppPreference(config *DesktopConfig, ctx context.Context) (SpreadsheetAppPreference, error) {
	if ctx == nil {
		return SpreadsheetAppPreference{}, errors.New("reading spreadsheet application preference requires a context")
	}
	if err := ctx.Err(); err != nil {
		return SpreadsheetAppPreference{}, err
	}
	if config == nil {
		return SpreadsheetAppPreference{}, errors.New("desktop configuration is unavailable")
	}
	values, err := config.Snapshot()
	if err != nil {
		return SpreadsheetAppPreference{}, err
	}
	pref := SpreadsheetAppPreference{}
	if sys, ok := values["System"].(map[string]any); ok {
		if raw, present := sys["SpreadsheetProgram"]; present && raw != nil {
			str, ok := raw.(string)
			if !ok {
				return SpreadsheetAppPreference{}, errors.New("System.SpreadsheetProgram must be a string path")
			}
			if !utf8.ValidString(str) || strings.ContainsRune(str, 0) {
				return SpreadsheetAppPreference{}, errors.New("System.SpreadsheetProgram contains invalid characters")
			}
			pref.ProgramPath = strings.TrimSpace(str)
		}
		if raw, present := sys["AutoOpenReports"]; present && raw != nil {
			switch v := raw.(type) {
			case bool:
				pref.AutoOpenExports = v
			case int:
				pref.AutoOpenExports = v != 0
			case string:
				if parsed, ok := parseLegacyBoolString(v); ok {
					pref.AutoOpenExports = parsed
				}
			}
		}
	}
	return pref, nil
}

// SetSpreadsheetAppPreference validates and atomically persists the user's
// spreadsheet application preference in config.yml.
func SetSpreadsheetAppPreference(config *DesktopConfig, ctx context.Context, pref SpreadsheetAppPreference) (SpreadsheetAppPreference, error) {
	if ctx == nil {
		return SpreadsheetAppPreference{}, errors.New("saving spreadsheet application preference requires a context")
	}
	if err := ctx.Err(); err != nil {
		return SpreadsheetAppPreference{}, err
	}
	if config == nil {
		return SpreadsheetAppPreference{}, errors.New("desktop configuration is unavailable")
	}
	cleaned := strings.TrimSpace(pref.ProgramPath)
	if !utf8.ValidString(cleaned) || strings.ContainsRune(cleaned, 0) {
		return SpreadsheetAppPreference{}, errors.New("spreadsheet application path must be valid text without NUL characters")
	}
	if cleaned != "" {
		if info, err := os.Stat(cleaned); err == nil && info.IsDir() {
			return SpreadsheetAppPreference{}, fmt.Errorf("spreadsheet application path %q is a directory, not an executable file", cleaned)
		}
	}
	normalized := SpreadsheetAppPreference{
		ProgramPath:     cleaned,
		AutoOpenExports: pref.AutoOpenExports,
	}
	if err := config.Update("System", map[string]any{
		"SpreadsheetProgram": normalized.ProgramPath,
		"AutoOpenReports":    normalized.AutoOpenExports,
	}); err != nil {
		return SpreadsheetAppPreference{}, err
	}
	return normalized, nil
}

// OpenFileInSpreadsheetApp opens an exported spreadsheet file (.xlsx/.xls/.ods/.csv/.tsv)
// using configuredApp when provided, or the operating system's default file handler when
// configuredApp is empty. Under -tags vpro_headless this safely returns
// ErrSpreadsheetLaunchUnavailableHeadless without spawning any subprocess.
func OpenFileInSpreadsheetApp(ctx context.Context, xlsxPath, configuredApp string) error {
	if ctx == nil {
		return errors.New("opening a spreadsheet requires a context")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	rawPath := strings.TrimSpace(xlsxPath)
	if rawPath == "" || !utf8.ValidString(rawPath) || strings.ContainsRune(rawPath, 0) {
		return errors.New("spreadsheet file path must be a non-empty valid path")
	}
	app := strings.TrimSpace(configuredApp)
	if !utf8.ValidString(app) || strings.ContainsRune(app, 0) {
		return errors.New("configured spreadsheet application path contains invalid characters")
	}
	ext := strings.ToLower(filepath.Ext(rawPath))
	if !allowedSpreadsheetExtensions[ext] {
		return fmt.Errorf("unsupported spreadsheet file extension %q; expected .xlsx, .xls, .ods, or .csv", ext)
	}
	absPath, err := filepath.Abs(rawPath)
	if err != nil {
		return fmt.Errorf("resolve spreadsheet file path: %w", err)
	}
	info, err := os.Stat(absPath)
	if err != nil {
		return fmt.Errorf("locate spreadsheet file %q: %w", absPath, err)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("spreadsheet path %q is not a regular file", absPath)
	}
	return openSpreadsheetPlatform(ctx, absPath, app)
}

// GetSpreadsheetAppPreference returns the saved spreadsheet launcher preference for the active context.
func (s *ContextService) GetSpreadsheetAppPreference(ctx context.Context, contextID string) (SpreadsheetAppPreference, error) {
	return WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) (SpreadsheetAppPreference, error) {
		return GetSpreadsheetAppPreference(plots.Projects.Preferences, ctx)
	})
}

// SetSpreadsheetAppPreference saves the spreadsheet launcher preference for the active context.
func (s *ContextService) SetSpreadsheetAppPreference(ctx context.Context, contextID string, pref SpreadsheetAppPreference) (SpreadsheetAppPreference, error) {
	return WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) (SpreadsheetAppPreference, error) {
		return SetSpreadsheetAppPreference(plots.Projects.Preferences, ctx, pref)
	})
}

// OpenReportInSpreadsheet opens filePath using the user's saved spreadsheet app preference (or OS default).
func (s *ContextService) OpenReportInSpreadsheet(ctx context.Context, contextID, filePath string) error {
	_, err := WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) (struct{}, error) {
		pref, err := GetSpreadsheetAppPreference(plots.Projects.Preferences, ctx)
		if err != nil {
			return struct{}{}, err
		}
		return struct{}{}, OpenFileInSpreadsheetApp(ctx, filePath, pref.ProgramPath)
	})
	return err
}
