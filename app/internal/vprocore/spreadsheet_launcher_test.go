package vprocore

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSpreadsheetAppPreferenceRoundTrip(t *testing.T) {
	ctx := context.Background()
	dataDir := t.TempDir()
	configDir := t.TempDir()
	cfg, err := OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		t.Fatalf("OpenDesktopConfig: %v", err)
	}

	initial, err := GetSpreadsheetAppPreference(cfg, ctx)
	if err != nil {
		t.Fatalf("GetSpreadsheetAppPreference initial: %v", err)
	}
	if initial.ProgramPath != "" || initial.AutoOpenExports {
		t.Fatalf("expected empty default spreadsheet preference, got %+v", initial)
	}

	fakeApp := filepath.Join(t.TempDir(), "libreoffice-calc")
	if err := os.WriteFile(fakeApp, []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatal(err)
	}

	saved, err := SetSpreadsheetAppPreference(cfg, ctx, SpreadsheetAppPreference{
		ProgramPath:     "  " + fakeApp + "  ",
		AutoOpenExports: true,
	})
	if err != nil {
		t.Fatalf("SetSpreadsheetAppPreference: %v", err)
	}
	if saved.ProgramPath != fakeApp || !saved.AutoOpenExports {
		t.Fatalf("unexpected saved preference: %+v", saved)
	}

	reloaded, err := GetSpreadsheetAppPreference(cfg, ctx)
	if err != nil {
		t.Fatalf("GetSpreadsheetAppPreference reload: %v", err)
	}
	if reloaded != saved {
		t.Fatalf("reloaded preference mismatch: got %+v want %+v", reloaded, saved)
	}

	// Clearing path back to OS default works cleanly.
	cleared, err := SetSpreadsheetAppPreference(cfg, ctx, SpreadsheetAppPreference{
		ProgramPath:     "",
		AutoOpenExports: false,
	})
	if err != nil {
		t.Fatalf("clear preference: %v", err)
	}
	if cleared.ProgramPath != "" || cleared.AutoOpenExports {
		t.Fatalf("expected cleared preference, got %+v", cleared)
	}

	// Reject directory path and NUL byte.
	if _, err := SetSpreadsheetAppPreference(cfg, ctx, SpreadsheetAppPreference{ProgramPath: dataDir}); err == nil {
		t.Fatal("expected error for directory ProgramPath")
	}
	if _, err := SetSpreadsheetAppPreference(cfg, ctx, SpreadsheetAppPreference{ProgramPath: "excel\x00.exe"}); err == nil {
		t.Fatal("expected error for NUL byte in ProgramPath")
	}
}

func TestOpenFileInSpreadsheetAppValidation(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	badExt := filepath.Join(dir, "script.sh")
	if err := os.WriteFile(badExt, []byte("echo hi\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := OpenFileInSpreadsheetApp(ctx, badExt, ""); err == nil || !strings.Contains(err.Error(), "unsupported spreadsheet file extension") {
		t.Fatalf("expected unsupported extension error, got %v", err)
	}
	if err := OpenFileInSpreadsheetApp(ctx, filepath.Join(dir, "missing.xlsx"), ""); err == nil {
		t.Fatal("expected missing file error")
	}
	cancelledCtx, cancel := context.WithCancel(ctx)
	cancel()
	if err := OpenFileInSpreadsheetApp(cancelledCtx, filepath.Join(dir, "a.xlsx"), ""); !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled, got %v", err)
	}
}
