package sqlutil

import (
	"bytes"
	"compress/gzip"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestReadWireFixturePlainAndGzipFallback(t *testing.T) {
	dir := t.TempDir()
	want := []byte(`{"fixture":"ok","rows":[1,2,3]}`)

	plainPath := filepath.Join(dir, "plain.json")
	if err := os.WriteFile(plainPath, want, 0600); err != nil {
		t.Fatal(err)
	}
	got, err := ReadWireFixture(plainPath)
	if err != nil {
		t.Fatalf("plain ReadWireFixture: %v", err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("plain mismatch: got %q want %q", got, want)
	}

	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	if _, err := gw.Write(want); err != nil {
		t.Fatal(err)
	}
	if err := gw.Close(); err != nil {
		t.Fatal(err)
	}

	onlyGzBase := filepath.Join(dir, "compressed.json")
	onlyGzPath := onlyGzBase + ".gz"
	if err := os.WriteFile(onlyGzPath, buf.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}

	// Fallback when callers pass the legacy .json path after compression.
	gotFallback, err := ReadWireFixture(onlyGzBase)
	if err != nil {
		t.Fatalf("fallback ReadWireFixture: %v", err)
	}
	if !bytes.Equal(gotFallback, want) {
		t.Fatalf("fallback mismatch: got %q want %q", gotFallback, want)
	}

	// Explicit .json.gz path also decodes directly.
	gotDirectGz, err := ReadWireFixture(onlyGzPath)
	if err != nil {
		t.Fatalf("direct gz ReadWireFixture: %v", err)
	}
	if !bytes.Equal(gotDirectGz, want) {
		t.Fatalf("direct gz mismatch: got %q want %q", gotDirectGz, want)
	}

	// Missing fixture preserves os.ErrNotExist.
	if _, err := ReadWireFixture(filepath.Join(dir, "missing.json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expected os.ErrNotExist, got %v", err)
	}
	if _, err := ReadWireFixture(filepath.Join("frontend", "tests", "fixtures", "definitely-missing-fixture.json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expected os.ErrNotExist for missing repo-relative fixture, got %v", err)
	}

	// Repo-relative fixture resolves cleanly without mutating process CWD.
	repoWire, err := ReadWireFixture(filepath.Join("frontend", "tests", "fixtures", "ordinaryAuditWire.json"))
	if err != nil || len(repoWire) == 0 {
		t.Fatalf("expected repo-relative ReadWireFixture to succeed from package CWD: len=%d err=%v", len(repoWire), err)
	}
}
