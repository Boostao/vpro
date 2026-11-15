package sivi

import (
	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

import (
	"context"
	"errors"
	"math"
	"reflect"
	"strings"
	"testing"
)

func TestSIVICombinedPlanningPresentationsGroupsAndAssignmentOrder(t *testing.T) {
	for _, extended := range []bool{false, true} {
		form := "SubVegA-SIVI_BC"
		if extended {
			form = "SubVegA-SIVI"
		}
		edits := []sourceform.SiviHeightEdit{
			{RowID: "1", Form: form, Column: "HeightA", Expected: vprotest.SiviReal(2), Value: vprotest.SiviReal(100)},
			{RowID: "6", Form: "SubVegD-SIVI", Column: "Cover9", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(9)},
			{RowID: "1", Form: form, Column: "HeightB", Expected: vprotest.MetadataText(""), Value: vprocore.ProjectMetadataCell{Storage: "null"}},
			{RowID: "4", Form: "SubVegC-SIVI", Column: "Cover6", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(6)},
			{RowID: "4", Form: "SubVegC-SIVI", Column: "Height6", Expected: vprotest.SiviReal(-3), Value: vprotest.SiviReal(100)},
			{RowID: "1", Form: form, Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(1)},
		}
		for _, column := range []string{"Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "TotalB"} {
			edits = append(edits, sourceform.SiviHeightEdit{RowID: "1", Form: form, Column: column, Expected: vprocore.ProjectMetadataCell{Storage: "null"}, Value: vprotest.SiviReal(2)})
		}
		for _, column := range []string{"Cover7", "Cover8"} {
			edits = append(edits, sourceform.SiviHeightEdit{RowID: "6", Form: "SubVegD-SIVI", Column: column, Expected: vprocore.ProjectMetadataCell{Storage: "null"}, Value: vprotest.SiviReal(2)})
		}
		if extended {
			edits = append(edits, sourceform.SiviHeightEdit{RowID: "2", Form: form, Column: "Cover5a", Expected: vprotest.SiviReal(-1), Value: vprotest.SiviReal(5)})
			for _, column := range []string{"Cover5b", "Cover5c"} {
				edits = append(edits, sourceform.SiviHeightEdit{RowID: "1", Form: form, Column: column, Expected: vprocore.ProjectMetadataCell{Storage: "null"}, Value: vprotest.SiviReal(2)})
			}
		}
		source := vprotest.SiviProjectionFixture()
		got, err := planSIVICombinedEdits(context.Background(), "P", extended, source, edits)
		if err != nil || len(got) != len(edits) {
			t.Fatal(extended, got, err)
		}
		for i, assignment := range got {
			if assignment.RowID != edits[i].RowID || assignment.Column != edits[i].Column ||
				!reflect.DeepEqual(assignment.Before, edits[i].Expected) || !reflect.DeepEqual(assignment.After, edits[i].Value) {
				t.Fatal("domain merge changed reviewed assignment order", i, assignment, edits[i])
			}
		}
		*got[0].Before.Real, *got[0].After.Real = 77, 88
		if !reflect.DeepEqual(source, vprotest.SiviProjectionFixture()) || *edits[0].Value.Real != 100 {
			t.Fatal("combined plan aliases caller/source")
		}
	}
	want := append(append([]string{}, sourceform.SiviCoverWritePolicy().Columns...), sourceform.SiviHeightWritePolicy().Columns...)
	if !reflect.DeepEqual(siviCombinedWritePolicy().Columns, want) {
		t.Fatal("combined restoration columns differ from existing domain policies")
	}
}

func TestSIVICombinedPlanningRejectsWrongFormsRowsDomainsAndDuplicates(t *testing.T) {
	valid := sourceform.SiviHeightEdit{RowID: "1", Form: "SubVegA-SIVI_BC", Column: "HeightA", Expected: vprotest.SiviReal(2), Value: vprotest.SiviReal(100)}
	cover := sourceform.SiviHeightEdit{RowID: "1", Form: valid.Form, Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(3)}
	for _, invalid := range []sourceform.SiviHeightEdit{
		{RowID: "1", Form: "SubVegA-SIVI", Column: "HeightA", Expected: vprotest.SiviReal(2), Value: vprotest.SiviReal(3)},
		{RowID: "1", Form: "SubVegA-SIVI", Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(3)},
		{RowID: "3", Form: valid.Form, Column: "HeightA", Expected: vprotest.SiviReal(5), Value: vprotest.SiviReal(3)},
		{RowID: "5", Form: "SubVegC-SIVI", Column: "Height6", Expected: vprotest.SiviReal(3), Value: vprotest.SiviReal(4)},
		{RowID: "8", Form: valid.Form, Column: "Cover1", Expected: vprotest.SiviReal(4), Value: vprotest.SiviReal(3)},
		{RowID: "9", Form: valid.Form, Column: "Cover1", Expected: vprotest.SiviReal(4), Value: vprotest.SiviReal(3)},
		{RowID: "01", Form: valid.Form, Column: "HeightA", Expected: vprotest.SiviReal(2), Value: vprotest.SiviReal(3)},
		{RowID: "1", Form: "SubVegC-SIVI", Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(3)},
		{RowID: "6", Form: "SubVegD-SIVI", Column: "Height6", Expected: vprocore.ProjectMetadataCell{Storage: "null"}, Value: vprotest.SiviReal(3)},
		{RowID: "1", Form: valid.Form, Column: "Cover5a", Expected: vprocore.ProjectMetadataCell{Storage: "null"}, Value: vprotest.SiviReal(3)},
		{RowID: "1", Form: valid.Form, Column: "Species", Expected: vprotest.MetadataText("S"), Value: vprotest.MetadataText("NEW")},
		{RowID: "1", Form: valid.Form, Column: "Collected", Expected: vprocore.ProjectMetadataCell{Storage: "null"}, Value: vprotest.MetadataText("C")},
		{RowID: "1", Form: valid.Form, Column: "ID", Expected: vprotest.MetadataInteger("0"), Value: vprotest.MetadataInteger("1")},
		{RowID: "1", Form: valid.Form, Column: "PlotNumber", Expected: vprotest.MetadataText("P"), Value: vprotest.MetadataText("Q")},
		{RowID: "1", Form: valid.Form, Column: "HeightA", Expected: vprotest.SiviReal(4), Value: vprotest.SiviReal(3)},
		{RowID: "1", Form: valid.Form, Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(100)},
		valid, cover,
	} {
		got, err := planSIVICombinedEdits(context.Background(), "P", false, vprotest.SiviProjectionFixture(), []sourceform.SiviHeightEdit{valid, cover, invalid})
		if err == nil || got != nil {
			t.Fatal("invalid combined tail leaked a partial plan", invalid, got, err)
		}
	}
	if got, err := planSIVICombinedEdits(context.Background(), "P", false, vprotest.SiviProjectionFixture(), nil); err == nil || got != nil {
		t.Fatal("empty combined plan accepted", got, err)
	}
}

func TestSIVICombinedPlanningSingleDomainAndNoopOrdering(t *testing.T) {
	height := sourceform.SiviHeightEdit{RowID: "1", Form: "SubVegA-SIVI_BC", Column: "HeightA", Expected: vprotest.SiviReal(2), Value: vprotest.SiviReal(100)}
	cover := sourceform.SiviHeightEdit{RowID: "1", Form: height.Form, Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(3)}
	for _, edits := range [][]sourceform.SiviHeightEdit{{height}, {cover}, {
		{RowID: "1", Form: height.Form, Column: "HeightB", Expected: vprotest.MetadataText(""), Value: vprotest.MetadataText("")}, cover, height,
	}} {
		got, err := planSIVICombinedEdits(context.Background(), "P", false, vprotest.SiviProjectionFixture(), edits)
		if err != nil {
			t.Fatal("empty opposite domain rejected valid edits", got, err)
		}
		want := []sourceform.SiviHeightEdit{}
		for _, edit := range edits {
			if !reflect.DeepEqual(edit.Expected, edit.Value) {
				want = append(want, edit)
			}
		}
		if len(got) != len(want) {
			t.Fatal("combined noop changed assignment count", got)
		}
		for i := range got {
			if got[i].Column != want[i].Column {
				t.Fatal("noop changed reviewed order", got)
			}
		}
	}
}

func TestSIVICombinedPlanningHeightBPhysicalBoundsAndHistoricalNoops(t *testing.T) {
	cover := sourceform.SiviHeightEdit{RowID: "1", Form: "SubVegA-SIVI_BC", Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(3)}
	for _, value := range []vprocore.ProjectMetadataCell{
		{Storage: "null"}, vprotest.MetadataText(""), vprotest.MetadataText("  literal  "),
		vprotest.MetadataText(strings.Repeat("x", 255)), vprotest.MetadataText(strings.Repeat("🌲", 127) + "x"),
	} {
		got, err := planSIVICombinedEdits(context.Background(), "P", false, vprotest.SiviProjectionFixture(), []sourceform.SiviHeightEdit{
			{RowID: "2", Form: cover.Form, Column: "HeightB", Expected: vprotest.MetadataText("  historical words  "), Value: value}, cover,
		})
		if err != nil || len(got) != 2 || !reflect.DeepEqual(got[0].After, value) {
			t.Fatal("valid HeightB was constrained/coerced", got, err)
		}
	}
	for _, value := range []vprocore.ProjectMetadataCell{
		vprotest.MetadataText(strings.Repeat("x", 256)), vprotest.MetadataText(strings.Repeat("🌲", 128)),
		vprotest.MetadataText("\xff"), vprotest.MetadataInteger("1"), vprotest.SiviReal(1),
	} {
		got, err := planSIVICombinedEdits(context.Background(), "P", false, vprotest.SiviProjectionFixture(), []sourceform.SiviHeightEdit{
			cover, {RowID: "1", Form: cover.Form, Column: "HeightB", Expected: vprotest.MetadataText(""), Value: value},
		})
		if err == nil || got != nil {
			t.Fatal("invalid HeightB leaked cover assignment", got, err)
		}
	}
	blob := "ff"
	for _, old := range []vprocore.ProjectMetadataCell{
		vprotest.MetadataText(strings.Repeat("x", 256)), vprotest.MetadataInteger("1"), vprotest.SiviReal(math.MaxFloat64),
		{Storage: "blob", BlobHex: &blob}, vprotest.SiviReal(100),
	} {
		source := vprotest.SiviProjectionFixture()
		source.Rows[0].Cells[3], source.Rows[0].Cells[7], source.Rows[0].Cells[14] = old, old, old
		source.Rows[0].Cells[4] = vprotest.SiviReal(0)
		edits := []sourceform.SiviHeightEdit{
			{RowID: "1", Form: cover.Form, Column: "HeightA", Expected: old, Value: old},
			{RowID: "1", Form: cover.Form, Column: "Cover2", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(3)},
			{RowID: "1", Form: cover.Form, Column: "Cover1", Expected: old, Value: old},
			{RowID: "1", Form: cover.Form, Column: "HeightB", Expected: old, Value: old},
		}
		got, err := planSIVICombinedEdits(context.Background(), "P", false, source, edits)
		if err != nil || len(got) != 1 || got[0].Column != "Cover2" {
			t.Fatal("unchanged historical invalids were assigned or rejected", got, err)
		}
		edits = append(edits, edits[0])
		if got, err := planSIVICombinedEdits(context.Background(), "P", false, source, edits); err == nil || got != nil {
			t.Fatal("duplicate historical noop escaped validation", got, err)
		}
	}
}

func TestSIVICombinedPlanningCancellationDiscardsMergedPlan(t *testing.T) {
	edits := []sourceform.SiviHeightEdit{
		{RowID: "1", Form: "SubVegA-SIVI_BC", Column: "HeightA", Expected: vprotest.SiviReal(2), Value: vprotest.SiviReal(100)},
		{RowID: "1", Form: "SubVegA-SIVI_BC", Column: "Cover1", Expected: vprotest.SiviReal(0), Value: vprotest.SiviReal(3)},
	}
	complete := false
	for remaining := 0; remaining < 300; remaining++ {
		ctx := &vprotest.VegetationCancelContext{Context: context.Background(), Remaining: remaining}
		got, err := planSIVICombinedEdits(ctx, "P", false, vprotest.SiviProjectionFixture(), edits)
		if err == nil {
			if len(got) != 2 {
				t.Fatal("successful combined plan incomplete", got)
			}
			complete = true
			break
		}
		if !errors.Is(err, context.Canceled) || got != nil {
			t.Fatal("canceled combined plan returned partial output", remaining, got, err)
		}
	}
	if !complete {
		t.Fatal("combined cancellation sweep never reached completion")
	}
	if got, err := planSIVICombinedEdits(nil, "P", false, vprotest.SiviProjectionFixture(), edits); err == nil || got != nil {
		t.Fatal("nil context accepted", got, err)
	}
}
