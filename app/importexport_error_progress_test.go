package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/interchange"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

func TestSanitizeImportExportErrorPreservesCancellationAndCleansTechnicalJargon(t *testing.T) {
	if sanitizeImportExportError(nil) != nil {
		t.Fatal("expected nil error to stay nil")
	}
	if !errors.Is(sanitizeImportExportError(context.Canceled), context.Canceled) {
		t.Fatal("expected context.Canceled to remain unwrapped/preserved")
	}
	if !errors.Is(sanitizeImportExportError(context.DeadlineExceeded), context.DeadlineExceeded) {
		t.Fatal("expected context.DeadlineExceeded to remain preserved")
	}

	cases := []struct {
		name      string
		in        error
		forbid    []string
		wantMatch string
	}{
		{
			name:      "picture_selection_chooser",
			in:        errors.New("picture selection requires its live native request window"),
			forbid:    []string{"picture selection"},
			wantMatch: "file selection requires an active desktop window",
		},
		{
			name:      "lstat_missing_file",
			in:        fmt.Errorf("resolve Access database: %w", &os.PathError{Op: "lstat", Path: "/tmp/missing.accdb", Err: os.ErrNotExist}),
			forbid:    []string{"lstat", "no such file or directory"},
			wantMatch: "was not found",
		},
		{
			name:      "corrupt_sqlite",
			in:        errors.New("database disk image is malformed"),
			forbid:    []string{"database disk image is malformed"},
			wantMatch: "damaged, incomplete, or not a valid SQLite file",
		},
		{
			name:      "truncated_xml",
			in:        errors.New("decode <Plot> #1: XML syntax error on line 1: unexpected EOF"),
			forbid:    []string{"unexpected EOF", "decode <Plot>"},
			wantMatch: "invalid XML formatting on line 1",
		},
		{
			name:      "sql_err_no_rows",
			in:        fmt.Errorf("lump table Missing_Lump not found: %w", sql.ErrNoRows),
			forbid:    []string{"sql: no rows in result set"},
			wantMatch: "lump table Missing_Lump not found",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := sanitizeImportExportError(tc.in)
			if got == nil {
				t.Fatal("expected non-nil error")
			}
			msg := got.Error()
			for _, banned := range tc.forbid {
				if strings.Contains(msg, banned) {
					t.Fatalf("sanitized error still contains %q: %q", banned, msg)
				}
			}
			if !strings.Contains(msg, tc.wantMatch) {
				t.Fatalf("sanitized error %q did not contain %q", msg, tc.wantMatch)
			}
		})
	}
}

func TestImportExportServiceHostileInputsReturnPlainLanguageErrors(t *testing.T) {
	dataDir := t.TempDir()
	configDir := t.TempDir()
	prefs, err := vprocorepkg.OpenDesktopConfig(dataDir, configDir)
	if err != nil {
		t.Fatal(err)
	}
	projects, err := vprocorepkg.NewSQLiteProjectService(dataDir, configDir, prefs)
	if err != nil {
		t.Fatal(err)
	}
	defer projects.CloseSQLiteContext()
	plots, err := vprocorepkg.NewPlotServiceWithPreferences(projects)
	if err != nil {
		t.Fatal(err)
	}
	contextSvc, err := NewContextService(projects, plots)
	if err != nil {
		t.Fatal(err)
	}
	svc := NewImportExportService(contextSvc, nil, nil, nil)
	ctx := context.Background()
	state, err := contextSvc.GetState(ctx)
	if err != nil {
		t.Fatal(err)
	}

	// 1. Server/headless ChooseAccessDatabaseFile must not mention "picture selection".
	if _, err := svc.ChooseAccessDatabaseFile(ctx, state.ContextID); err == nil {
		t.Fatal("expected ChooseAccessDatabaseFile to fail without a desktop window")
	} else if strings.Contains(err.Error(), "picture selection") || !strings.Contains(err.Error(), "file selection") {
		t.Fatalf("unexpected ChooseAccessDatabaseFile error: %q", err.Error())
	}

	// 2. Hostile TurboVeg corrupt SQLite & truncated XML must return plain-language errors.
	badSqlite := filepath.Join(t.TempDir(), "trunc_tv.sqlite")
	if err := os.WriteFile(badSqlite, []byte("SQLite format 3\x00corrupt-bytes"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.ImportTurboVeg(ctx, state.ContextID, interchange.TurboVegImportRequest{
		SourcePath:    badSqlite,
		TargetProject: "BadTvSqlite",
	}); err == nil {
		t.Fatal("expected corrupt TurboVeg SQLite to fail")
	} else if strings.Contains(err.Error(), "database disk image is malformed") {
		t.Fatalf("ImportTurboVeg leaked raw SQLite error: %q", err.Error())
	}

	badXML := filepath.Join(t.TempDir(), "bad_tv.xml")
	if err := os.WriteFile(badXML, []byte("<Plot_package><Plots><Plot releve_nr=\"1\">"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.ImportTurboVeg(ctx, state.ContextID, interchange.TurboVegImportRequest{
		SourcePath:    badXML,
		TargetProject: "BadTvXml",
	}); err == nil {
		t.Fatal("expected truncated TurboVeg XML to fail")
	} else if strings.Contains(err.Error(), "unexpected EOF") {
		t.Fatalf("ImportTurboVeg leaked raw XML EOF error: %q", err.Error())
	}
}
