package cloudsync

import (
	"strings"
	"testing"
)

func TestUXCloud006SubsetLimitRequiresRegionalFilterOrFullCheckout(t *testing.T) {
	// Limit alone without a regional filter or AllowFullCheckout must be rejected.
	_, _, err := buildSubsetWhereClause(SubsetFilter{Limit: 250}, true)
	if err == nil {
		t.Fatal("expected Limit-only SubsetFilter without AllowFullCheckout to fail")
	}
	if !strings.Contains(err.Error(), "regional filter") || strings.Contains(err.Error(), "or Limit") {
		t.Fatalf("unexpected Limit-only error message: %v", err)
	}

	// Limit combined with AllowFullCheckout is valid (caps full checkout).
	whereSQL, args, err := buildSubsetWhereClause(SubsetFilter{
		Limit:             250,
		AllowFullCheckout: true,
	}, true)
	if err != nil {
		t.Fatalf("expected Limit + AllowFullCheckout to succeed, got %v", err)
	}
	if whereSQL != "" || len(args) != 0 {
		t.Fatalf("expected empty WHERE clause for AllowFullCheckout, got whereSQL=%q args=%v", whereSQL, args)
	}

	// Limit combined with any regional filter is valid.
	whereSQL, args, err = buildSubsetWhereClause(SubsetFilter{
		Zones: []string{"CWH"},
		Limit: 250,
	}, false)
	if err != nil {
		t.Fatalf("expected Zone + Limit to succeed, got %v", err)
	}
	if !strings.Contains(whereSQL, `"Zone" = ANY($1)`) || len(args) != 1 {
		t.Fatalf("unexpected Zone + Limit query: whereSQL=%q args=%v", whereSQL, args)
	}

	// Negative Limit is rejected.
	if _, _, err := buildSubsetWhereClause(SubsetFilter{
		Zones: []string{"CWH"},
		Limit: -1,
	}, false); err == nil {
		t.Fatal("expected negative Limit to fail")
	}
}

func TestUXCloud006SnapshotTagValidationMatchesFrontend80CharContract(t *testing.T) {
	for _, validTag := range []string{
		"A",
		"BECMaster_2026.11-rc1",
		strings.Repeat("a", 64),
		strings.Repeat("b", 65),
		strings.Repeat("Z", 80),
	} {
		got, err := validateSnapshotTag(validTag)
		if err != nil || got != validTag {
			t.Fatalf("expected snapshot tag %q (len=%d) to pass, got=%q err=%v", validTag, len(validTag), got, err)
		}
	}

	for _, paddedOrEmpty := range []string{"", "   ", " BECMaster_2026", "BECMaster_2026 "} {
		if _, err := validateSnapshotTag(paddedOrEmpty); err == nil || !strings.Contains(err.Error(), "leading or trailing spaces") {
			t.Fatalf("expected %q to fail whitespace/empty check, got %v", paddedOrEmpty, err)
		}
	}

	for _, badTag := range []string{
		strings.Repeat("X", 81),
		strings.Repeat("X", 120),
		"bad/slash",
		"bad space",
		"bad:colon",
	} {
		if _, err := validateSnapshotTag(badTag); err == nil || !strings.Contains(err.Error(), "max 80 characters") {
			t.Fatalf("expected %q (len=%d) to fail 80-char charset check, got %v", badTag, len(badTag), err)
		}
	}

	// Verify CreateBECMasterSnapshot accepts 65..80 char tags past tag validation (failing only on unconfigured pool).
	mgr := NewManager(t.TempDir(), func(string) (string, bool) { return "", false })
	defer mgr.Close()

	for _, lenN := range []int{65, 80} {
		_, err := mgr.CreateBECMasterSnapshot(t.Context(), nil, "", CreateSnapshotRequest{
			SnapshotTag: strings.Repeat("S", lenN),
		}, nil)
		if err == nil || !strings.Contains(err.Error(), "custodian admin credentials are not configured") {
			t.Fatalf("expected %d-char tag to pass tag validation and stop at unconfigured credentials, got %v", lenN, err)
		}
	}

	_, overErr := mgr.CreateBECMasterSnapshot(t.Context(), nil, "", CreateSnapshotRequest{
		SnapshotTag: strings.Repeat("S", 81),
	}, nil)
	if overErr == nil || !strings.Contains(overErr.Error(), "max 80 characters") {
		t.Fatalf("expected 81-char tag to fail CreateBECMasterSnapshot tag validation, got %v", overErr)
	}
}
