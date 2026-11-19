package twopage

import (
	"context"
	"database/sql"
	"errors"
	"reflect"
	"testing"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sourceform/sftest"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func twoPageEntryOptionalFixture(column string, value vprocore.ProjectMetadataCell) (*sourceform.SourceParentProjection, sourceform.SourceParentScalarAssignment, sourceform.SourceParentSharedReference, TwoPageEntryCodeAcknowledgementInternal) {
	original := &sourceform.SourceParentProjection{ContextID: "owned", Project: "Sample", Plot: "108050", Form: "FS882-8x6XL",
		Rows: []sourceform.SourceParentRow{{}}}
	assignment := sourceform.SourceParentScalarAssignment{ContextID: "owned", Table: "Sample_Env", RowID: "1", Column: column,
		Before: vprotest.MetadataText("historical"), After: value}
	reference := sourceform.SourceParentSharedReference{Column: column, ListName: column, Available: true,
		Source: "independent current source", Definitions: vprocore.ProjectMetadataTable{
			Columns: []vprocore.ProjectMetadataColumn{{Name: "Item", DeclaredType: "TEXT"}}, Rows: []vprocore.ProjectMetadataRow{}},
		Choices: []sourceform.SourceParentSharedReferenceChoice{sftest.TwoPageEntryReferenceChoice("XX")}}
	acknowledgement := TwoPageEntryCodeAcknowledgementInternal{ContextID: original.ContextID, Project: original.Project,
		Plot: original.Plot, Form: original.Form, Table: assignment.Table, RowID: assignment.RowID, Column: column,
		Expected: assignment.Before, Value: value, Reference: reference}
	return original, assignment, reference, acknowledgement
}

func TestTwoPageEntryOptionalAcknowledgementLiteralValueAndFreshIdentity(t *testing.T) {
	original, assignment, reference, acknowledgement := twoPageEntryOptionalFixture("Zone", vprotest.MetadataText("Ab"))
	before := *original
	tx := &sql.Tx{}
	reader := func(context.Context, *sql.Tx, TwoPageEntryReferenceField) (sourceform.SourceParentSharedReference, error) {
		return reference, nil
	}
	if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original,
		[]sourceform.SourceParentScalarAssignment{assignment}, nil, reader); err == nil {
		t.Fatal("unmatched raw code was approved without acknowledgement")
	}
	if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original,
		[]sourceform.SourceParentScalarAssignment{assignment}, []TwoPageEntryCodeAcknowledgementInternal{acknowledgement}, reader); err != nil {
		t.Fatal("exact original/draft/reference acknowledgement rejected", err)
	}
	if !reflect.DeepEqual(*original, before) || *assignment.After.Text != "Ab" {
		t.Fatal("approval normalized the original or literal case")
	}
	for _, failure := range []string{"context", "project", "plot", "form", "table", "row", "expected", "value",
		"source", "description", "NULL metadata", "empty metadata", "availability", "duplicate", "mandatory", "foreign", "unused"} {
		current := acknowledgement
		current.Reference = reference
		current.Reference.Choices = append([]sourceform.SourceParentSharedReferenceChoice(nil), reference.Choices...)
		currentAssignment := assignment
		switch failure {
		case "context":
			current.ContextID = "another editor"
		case "project":
			current.Project = "another project"
		case "plot":
			current.Plot = "another plot"
		case "form":
			current.Form = "FS882-8x6XL-CHARS"
		case "table":
			current.Table = "Sample_Admin"
		case "row":
			current.RowID = "2"
		case "expected":
			current.Expected = vprotest.MetadataText("another original")
		case "value":
			current.Value = vprotest.MetadataText("another draft")
		case "source":
			current.Reference.Source = "another source context"
		case "description":
			text := "changed description"
			current.Reference.Choices[0].Description = &text
		case "NULL metadata":
			current.Reference.Choices[0].Description = nil
			current.Reference.Definitions.Rows = []vprocore.ProjectMetadataRow{{RowID: "1", Cells: []vprocore.ProjectMetadataCell{{Storage: "null"}}}}
		case "empty metadata":
			current.Reference.Definitions.Rows = []vprocore.ProjectMetadataRow{{RowID: "1", Cells: []vprocore.ProjectMetadataCell{vprotest.MetadataText("")}}}
		case "availability":
			current.Reference.Available = false
			current.Reference.Diagnostic = "catalogue unavailable"
		case "mandatory":
			current.Column = "Exposure1"
		case "foreign":
			current.Column = "FieldNumber"
		case "unused":
			currentAssignment.Column = "FieldNumber"
		}
		acknowledgements := []TwoPageEntryCodeAcknowledgementInternal{current}
		if failure == "duplicate" {
			acknowledgements = append(acknowledgements, current)
		}
		if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original,
			[]sourceform.SourceParentScalarAssignment{currentAssignment}, acknowledgements, reader); err == nil {
			t.Fatal("stale/foreign acknowledgement accepted", failure)
		}
	}
	reference.Choices = []sourceform.SourceParentSharedReferenceChoice{sftest.TwoPageEntryReferenceChoice("aB"), sftest.TwoPageEntryReferenceChoice("aB")}
	if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original,
		[]sourceform.SourceParentScalarAssignment{assignment}, nil, reader); err != nil {
		t.Fatal("existing ASCII-insensitive optional matching changed or collapsed duplicates", err)
	}
}

func TestTwoPageEntryOptionalAcknowledgementAvailabilityCancellationAndClearing(t *testing.T) {
	original, assignment, reference, acknowledgement := twoPageEntryOptionalFixture("Zone", vprotest.MetadataText("Ab"))
	tx := &sql.Tx{}
	for _, failure := range []string{"read", "identity", "policy", "unexplained availability", "cancel"} {
		ctx, cancel := context.WithCancel(context.Background())
		reader := func(context.Context, *sql.Tx, TwoPageEntryReferenceField) (sourceform.SourceParentSharedReference, error) {
			current := reference
			switch failure {
			case "read":
				return sourceform.SourceParentSharedReference{}, errors.New("reference read failed")
			case "identity":
				current.ListName = "another source"
			case "policy":
				current.Required = true
			case "unexplained availability":
				current.Available = false
			case "cancel":
				cancel()
			}
			return current, nil
		}
		err := ApproveTwoPageEntryOptionalReferences(ctx, tx, original, []sourceform.SourceParentScalarAssignment{assignment},
			[]TwoPageEntryCodeAcknowledgementInternal{acknowledgement}, reader)
		cancel()
		if err == nil || (failure == "cancel" && !errors.Is(err, context.Canceled)) {
			t.Fatal("optional reference error or cancellation was hidden", failure, err)
		}
	}
	reference.Available, reference.Diagnostic = false, "choices unavailable; raw value not checked"
	acknowledgement.Reference = reference
	reader := func(context.Context, *sql.Tx, TwoPageEntryReferenceField) (sourceform.SourceParentSharedReference, error) {
		return reference, nil
	}
	if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original, []sourceform.SourceParentScalarAssignment{assignment},
		[]TwoPageEntryCodeAcknowledgementInternal{acknowledgement}, reader); err != nil {
		t.Fatal("explicitly acknowledged unavailable optional catalogue rejected", err)
	}
	if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original, []sourceform.SourceParentScalarAssignment{assignment},
		nil, reader); err == nil {
		t.Fatal("unavailable optional code silently approved")
	}
	cleared := assignment
	cleared.After = vprocore.ProjectMetadataCell{Storage: "null"}
	reads := 0
	reader = func(context.Context, *sql.Tx, TwoPageEntryReferenceField) (sourceform.SourceParentSharedReference, error) {
		reads++
		return reference, nil
	}
	if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original, []sourceform.SourceParentScalarAssignment{cleared},
		nil, reader); err != nil || reads != 0 {
		t.Fatal("NULL clearing unnecessarily read an optional catalogue", reads, err)
	}
	if err := ApproveTwoPageEntryOptionalReferences(context.Background(), tx, original, []sourceform.SourceParentScalarAssignment{cleared},
		[]TwoPageEntryCodeAcknowledgementInternal{acknowledgement}, reader); err == nil {
		t.Fatal("cleared draft reused an old acknowledgement")
	}
	for _, missing := range []string{"tx", "original", "rows", "reader"} {
		currentTx, currentOriginal, currentReader := tx, original, TwoPageEntryCodeReader(reader)
		if missing == "tx" {
			currentTx = nil
		} else if missing == "original" {
			currentOriginal = nil
		} else if missing == "rows" {
			copy := *original
			copy.Rows = nil
			currentOriginal = &copy
		} else {
			currentReader = nil
		}
		if err := ApproveTwoPageEntryOptionalReferences(context.Background(), currentTx, currentOriginal, nil, nil, currentReader); err == nil {
			t.Fatal("optional boundary accepted missing ownership", missing)
		}
	}
}

func TestTwoPageEntryOptionalReferenceNumberAndTextDomains(t *testing.T) {
	fields, err := twoPageEntryReferenceFields("FS882-8x6XL")
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range fields {
		if field.Column == "LocationAccuracy" {
			for _, raw := range []string{"0", "32767"} {
				if got, err := TwoPageEntryReferenceCode(field, vprotest.MetadataInteger(raw)); err != nil || got != raw {
					t.Fatal("accepted INTEGER reference changed representation", raw, got, err)
				}
			}
			for _, raw := range []string{"-1", "-32768", "32768", "-32769", "01", "+1", "1.0"} {
				if _, err := TwoPageEntryReferenceCode(field, vprotest.MetadataInteger(raw)); err == nil {
					t.Fatal("invalid/noncanonical numeric reference accepted", raw)
				}
			}
			if !twoPageEntryOptionalReferenceMatch(field, "1", sftest.TwoPageEntryReferenceChoice("1")) ||
				twoPageEntryOptionalReferenceMatch(field, "1", sftest.TwoPageEntryReferenceChoice("01")) {
				t.Fatal("numeric catalogue representation silently rewritten")
			}
		}
		if field.Column == "Zone" {
			for _, value := range []vprocore.ProjectMetadataCell{vprotest.MetadataText(""), vprotest.MetadataText("12345"), vprotest.MetadataText(string([]byte{0xff})),
				vprotest.MetadataInteger("1")} {
				if _, err := TwoPageEntryReferenceCode(field, value); err == nil {
					t.Fatal("optional text physical failure bypassed approval", value)
				}
			}
			if twoPageEntryOptionalReferenceMatch(field, "k", sftest.TwoPageEntryReferenceChoice("\u212a")) {
				t.Fatal("Unicode folding widened established ASCII matching")
			}
		}
	}
}
