package references

import (
	"context"
	"os"
	"strings"
	"testing"
)

func TestBECService_ZoneOnlyAndSearchSiteSeries(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "vpro-bec-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tempDir)

	svc, err := NewBECService(tempDir)
	if err != nil {
		t.Fatalf("NewBECService failed: %v", err)
	}
	defer svc.Close()

	zone := "CWH"
	byZone, err := svc.ListBECSiteSeries(context.Background(), &zone, nil)
	if err != nil {
		t.Fatalf("ListBECSiteSeries(zone-only) failed: %v", err)
	}
	if len(byZone) == 0 {
		t.Fatalf("expected CWH site series when subZone == nil, got empty")
	}
	for _, item := range byZone {
		if item.Zone == nil || !strings.EqualFold(*item.Zone, "CWH") {
			t.Fatalf("zone-only query returned unexpected row zone: %+v", item.Zone)
		}
	}

	allRows, err := svc.ListBECSiteSeries(context.Background(), nil, nil)
	if err != nil {
		t.Fatalf("ListBECSiteSeries(nil, nil) failed: %v", err)
	}
	if len(allRows) <= len(byZone) {
		t.Fatalf("expected all rows (%d) > CWH-only rows (%d)", len(allRows), len(byZone))
	}

	searched, err := svc.SearchBECSiteSeries(context.Background(), &zone, nil, "Blueberry", 15)
	if err != nil || len(searched) == 0 {
		t.Fatalf("SearchBECSiteSeries failed: len=%d err=%v", len(searched), err)
	}
}
