package sivi_test

import (
	"context"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/sivi"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestUxEnv005CreateSIVIPlotRejectsLeadingTrailingWhitespaceAndInvalidCalendarDate(t *testing.T) {
	svc, state := vprotest.ContextServiceFixture(t)
	ctx := context.Background()

	for _, padded := range []string{"00888 ", " 00887", "\tSV01", "SV02\n"} {
		_, err := sivi.CreateSIVIPlot(svc, ctx, state.ContextID, sivi.CreateSIVIPlotRequest{
			PlotNumber: padded,
			PlotType:   "Ground",
		})
		if err == nil || !strings.Contains(err.Error(), "whitespace") {
			t.Fatalf("CreateSIVIPlot(%q): expected whitespace error, got %v", padded, err)
		}
	}

	for _, badDate := range []string{"not-a-date", "2026-02-30", "2026-13-01", "07/19/2026"} {
		_, err := sivi.CreateSIVIPlot(svc, ctx, state.ContextID, sivi.CreateSIVIPlotRequest{
			PlotNumber: "SVDATE1",
			PlotType:   "Ground",
			Date:       badDate,
		})
		if err == nil || !strings.Contains(err.Error(), "YYYY-MM-DD") {
			t.Fatalf("CreateSIVIPlot with Date=%q: expected YYYY-MM-DD error, got %v", badDate, err)
		}
	}

	db, err := sqlutil.OpenReadOnly(state.ProjectPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	var cnt int
	if err := db.QueryRow(`SELECT COUNT(*) FROM Sample_Env WHERE PlotNumber LIKE '%0088%' OR PlotNumber = 'SVDATE1'`).Scan(&cnt); err != nil {
		t.Fatal(err)
	}
	if cnt != 0 {
		t.Fatalf("expected 0 rows written for rejected SIVI plot creations, got %d", cnt)
	}
}
