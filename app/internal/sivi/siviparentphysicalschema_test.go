package sivi

import (
	"context"
	"database/sql"
	"reflect"
	"testing"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sourceform/sftest"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func TestSIVIParentPhysicalSchemaPreflight(t *testing.T) {
	for _, table := range []string{"Sample_Env", "Sample_Admin"} {
		for _, column := range []string{"rowid", "_rowid_", "oid", "ExtraGenerated"} {
			t.Run(table+"/"+column, func(t *testing.T) {
				service, state := vprotest.ContextServiceFixture(t)
				original, err := sourceform.ReadSIVIParent(service, context.Background(), state.ContextID, "108050")
				if err != nil {
					t.Fatal(err)
				}
				actions := sftest.SiviActionProposalEdits(original)
				db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(state.ProjectPath, "rw"))
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() {
					if err := db.Close(); err != nil {
						t.Error(err)
					}
				})
				quoted := vprocore.QuoteHeaderIdentifier(table)
				orig := vprocore.QuoteHeaderIdentifier(table + "_orig")
				isGenerated := column != "rowid" && column != "_rowid_" && column != "oid"
				addSQL := "ALTER TABLE " + quoted + " RENAME TO " + orig +
					"; CREATE TABLE " + quoted + " AS SELECT *, 99 AS " + vprocore.QuoteHeaderIdentifier(column) + " FROM " + orig
				restoreSQL := "DROP TABLE " + quoted + "; ALTER TABLE " + orig + " RENAME TO " + quoted
				if isGenerated {
					addSQL = "ALTER TABLE " + quoted + " ADD COLUMN " + vprocore.QuoteHeaderIdentifier(column) + " INTEGER GENERATED ALWAYS AS (99) VIRTUAL"
					restoreSQL = "ALTER TABLE " + quoted + " DROP COLUMN " + vprocore.QuoteHeaderIdentifier(column)
				}
				if _, err := db.Exec(addSQL); err != nil {
					t.Fatal(err)
				}
				files := vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
				if got, err := sourceform.ReadSIVIParent(service, context.Background(), state.ContextID, "108050"); err == nil || got != nil {
					t.Fatalf("generated/hidden/shadowed schema returned parent: result=%t error=%v", got != nil, err)
				}
				if got, err := sourceform.PrepareSIVIParentActionProposal(service, context.Background(), state.ContextID, "108050", nil, nil, nil, nil, actions); err == nil || got != nil {
					t.Fatalf("generated schema returned action proposal: result=%t error=%v", got != nil, err)
				}
				vprotest.AssertProfileSUFiles(t, service, files)
				if _, err := db.Exec(restoreSQL); err != nil {
					t.Fatal(err)
				}
				retry, err := sourceform.ReadSIVIParent(service, context.Background(), state.ContextID, "108050")
				if err != nil || !reflect.DeepEqual(retry, original) {
					t.Fatal("physical schema restoration discarded attachments or changed originals", retry, original, err)
				}
				files = vprotest.DatabaseBytes(t, service.Projects.Sqlite.Attachments)
				proposal, err := sourceform.PrepareSIVIParentActionProposal(service, context.Background(), state.ContextID, "108050", nil, nil, nil, nil, actions)
				if err != nil || proposal == nil || !reflect.DeepEqual(proposal.Original, original) {
					t.Fatal("restored schema could not retry exact source planning", proposal, err)
				}
				vprotest.AssertProfileSUFiles(t, service, files)
			})
		}
	}
}
