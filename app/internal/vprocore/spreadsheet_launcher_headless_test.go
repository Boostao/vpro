//go:build vpro_headless

package vprocore

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestOpenFileInSpreadsheetAppHeadlessSafeError(t *testing.T) {
	ctx := context.Background()
	xlsx := filepath.Join(t.TempDir(), "report.xlsx")
	if err := os.WriteFile(xlsx, []byte("PK\x03\x04"), 0o600); err != nil {
		t.Fatal(err)
	}
	err := OpenFileInSpreadsheetApp(ctx, xlsx, "")
	if !errors.Is(err, ErrSpreadsheetLaunchUnavailableHeadless) {
		t.Fatalf("expected ErrSpreadsheetLaunchUnavailableHeadless, got %v", err)
	}
}
