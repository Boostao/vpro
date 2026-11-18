package accessreader

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// VPro15_Audit in the VPro 1.5 template has exactly 3 rows. *.accdb files are gitignored, so the
// fixture is resolved from VPRO_ACCESS_FIXTURE or the local reference archive and skipped if absent.
const quarantineTable = "VPro15_Audit"

func quarantineFixture(t *testing.T) string {
	t.Helper()
	candidates := []string{os.Getenv("VPRO_ACCESS_FIXTURE")}
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates, filepath.Join(home, "Work", "VPRO_ACCESS", "VPro64", "Templates", "TemplateVPro15.accdb"))
	}
	for _, c := range candidates {
		if c != "" {
			if _, err := os.Stat(c); err == nil {
				return c
			}
		}
	}
	t.Skip("TemplateVPro15.accdb fixture not available (set VPRO_ACCESS_FIXTURE)")
	return ""
}

func readAllRows(t *testing.T, db *DB) []Row {
	t.Helper()
	_, rows, err := db.ReadAll(quarantineTable)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 {
		t.Fatalf("fixture changed: want 3 rows in %s, got %d", quarantineTable, len(rows))
	}
	return rows
}

// ENG-GO-001: quarantining a row after go_mdb_next returned 1 must not also skip the next row.
func TestPostFetchQuarantinePreservesAdjacentRows(t *testing.T) {
	db, err := Open(quarantineFixture(t))
	if err != nil {
		t.Fatal(err)
	}
	all := readAllRows(t, db)
	for bad := 1; bad <= len(all); bad++ {
		reader, err := db.Scan(quarantineTable)
		if err != nil {
			t.Fatal(err)
		}
		reader.EnableRowQuarantine()
		reader.postFetchCheck = func(rowNumber int, _ Row) error {
			if rowNumber == bad {
				return errors.New("forced post-fetch quarantine")
			}
			return nil
		}
		var got []Row
		for reader.Next() {
			got = append(got, append(Row(nil), reader.Row()...))
		}
		if err := reader.Err(); err != nil {
			t.Fatal(err)
		}
		reader.Close()
		want := append(append([]Row(nil), all[:bad-1]...), all[bad:]...)
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("quarantining row %d: yielded %d rows, want the %d other rows unchanged and in order", bad, len(got), len(want))
		}
		if len(reader.Quarantined) != 1 || reader.Quarantined[0].RowNumber != bad {
			t.Fatalf("quarantining row %d: Quarantined = %+v", bad, reader.Quarantined)
		}
		if len(got)+len(reader.Quarantined) != len(all) {
			t.Fatalf("imported + quarantined = %d, want total %d", len(got)+len(reader.Quarantined), len(all))
		}
	}
}
