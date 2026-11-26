//go:build !vpro_headless

package vprocore

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestOpenFileInSpreadsheetAppDesktopLaunch(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	xlsx := filepath.Join(dir, "report.xlsx")
	if err := os.WriteFile(xlsx, []byte("PK\x03\x04"), 0o600); err != nil {
		t.Fatal(err)
	}
	fakeExe := filepath.Join(dir, "calc-bin")
	if err := os.WriteFile(fakeExe, []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatal(err)
	}

	orig := spreadsheetCommandStarter
	t.Cleanup(func() { spreadsheetCommandStarter = orig })

	var gotName string
	var gotArgs []string
	spreadsheetCommandStarter = func(name string, args ...string) error {
		gotName = name
		gotArgs = append([]string(nil), args...)
		return nil
	}

	// OS default handler
	if err := OpenFileInSpreadsheetApp(ctx, xlsx, ""); err != nil {
		t.Fatalf("OpenFileInSpreadsheetApp default: %v", err)
	}
	switch runtime.GOOS {
	case "windows":
		if gotName != "cmd" || len(gotArgs) != 4 || gotArgs[0] != "/c" || gotArgs[1] != "start" || gotArgs[2] != "" || gotArgs[3] != xlsx {
			t.Fatalf("unexpected windows launch: %q %v", gotName, gotArgs)
		}
	case "darwin":
		if gotName != "open" || len(gotArgs) != 1 || gotArgs[0] != xlsx {
			t.Fatalf("unexpected darwin launch: %q %v", gotName, gotArgs)
		}
	default:
		if gotName != "xdg-open" || len(gotArgs) != 1 || gotArgs[0] != xlsx {
			t.Fatalf("unexpected unix launch: %q %v", gotName, gotArgs)
		}
	}

	// Cross-OS check: Windows launcher avoids rundll32 FileProtocolHandler path edge cases (, # %)
	winPath := `C:\Exports\BEC, #1 100% report.xlsx`
	winCmd, winArgs, err := buildSpreadsheetLaunchCommand("windows", winPath, "")
	if err != nil {
		t.Fatalf("buildSpreadsheetLaunchCommand windows: %v", err)
	}
	if winCmd != "cmd" || len(winArgs) != 4 || winArgs[0] != "/c" || winArgs[1] != "start" || winArgs[2] != "" || winArgs[3] != filepath.Clean(winPath) {
		t.Fatalf("unexpected windows command: %q %v", winCmd, winArgs)
	}

	// User-configured spreadsheet executable
	if err := OpenFileInSpreadsheetApp(ctx, xlsx, fakeExe); err != nil {
		t.Fatalf("OpenFileInSpreadsheetApp configured: %v", err)
	}
	if gotName != fakeExe || len(gotArgs) != 1 || gotArgs[0] != xlsx {
		t.Fatalf("unexpected configured launch: %q %v", gotName, gotArgs)
	}
}
