//go:build !vpro_headless

package vprocore

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// spreadsheetCommandStarter is injectable in tests so command construction can be
// verified without spawning desktop applications during go test.
var spreadsheetCommandStarter = defaultStartSpreadsheetCommand

func defaultStartSpreadsheetCommand(name string, args ...string) error {
	return exec.Command(name, args...).Start()
}

func buildSpreadsheetLaunchCommand(goos, absFilePath, configuredApp string) (string, []string, error) {
	cleanPath := filepath.Clean(absFilePath)
	if configuredApp != "" {
		resolved := configuredApp
		if filepath.IsAbs(configuredApp) {
			info, err := os.Stat(configuredApp)
			if err != nil {
				return "", nil, fmt.Errorf("configured spreadsheet application %q was not found: %w", configuredApp, err)
			}
			if info.IsDir() {
				if goos == "darwin" && filepath.Ext(configuredApp) == ".app" {
					return "open", []string{"-a", configuredApp, cleanPath}, nil
				}
				return "", nil, fmt.Errorf("configured spreadsheet application %q is a directory", configuredApp)
			}
		} else {
			lookedUp, err := exec.LookPath(configuredApp)
			if err != nil {
				return "", nil, fmt.Errorf("configured spreadsheet application %q was not found on PATH: %w", configuredApp, err)
			}
			resolved = lookedUp
		}
		return resolved, []string{cleanPath}, nil
	}

	switch goos {
	case "windows":
		return "rundll32.exe", []string{"url.dll,FileProtocolHandler", cleanPath}, nil
	case "darwin":
		return "open", []string{cleanPath}, nil
	default:
		return "xdg-open", []string{cleanPath}, nil
	}
}

func openSpreadsheetPlatform(ctx context.Context, absPath, configuredApp string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	cmdName, args, err := buildSpreadsheetLaunchCommand(runtime.GOOS, absPath, configuredApp)
	if err != nil {
		return err
	}
	if err := spreadsheetCommandStarter(cmdName, args...); err != nil {
		return fmt.Errorf("launch spreadsheet application (%s): %w", filepath.Base(cmdName), err)
	}
	return nil
}
