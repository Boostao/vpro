package reportcore

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

// ReadReportStringPreference reads a single string preference under ReportOptions.<key>
// under the DesktopConfig mutex lease without applying fallback defaults or mutating disk.
func ReadReportStringPreference(s *vprocore.DesktopConfig, ctx context.Context, label, key string) (string, error) {
	if ctx == nil {
		return "", errors.New(label + " preferences require a context")
	}
	if s == nil {
		return "", errors.New(label + " preference configuration is unavailable")
	}
	if err := sqlutil.AcquireMutexLease(ctx, &s.Mu); err != nil {
		return "", err
	}
	defer s.Mu.Unlock()
	values, err := s.ReadLocked()
	if err != nil {
		return "", err
	}
	val, err := vprocore.ConfigString(values, "ReportOptions", key)
	if err != nil {
		return "", err
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return val, nil
}

// ValidateReportTitle rejects invalid UTF-8 and NUL runes in a report title.
func ValidateReportTitle(fieldLabel, value string) error {
	if !utf8.ValidString(value) || strings.ContainsRune(value, 0) {
		return errors.New(fieldLabel + " requires complete Unicode without NUL; no repair or normalization")
	}
	return nil
}

// CompareAndSetReportStringPreference atomically compare-and-swaps ReportOptions.<key>
// after verifying valid UTF-8 without NUL bytes.
func CompareAndSetReportStringPreference(s *vprocore.DesktopConfig, ctx context.Context, label, fieldLabel, key, expected, proposed string) (vprocore.ConfigStringPreferenceUpdate, error) {
	if ctx == nil {
		return vprocore.ConfigStringPreferenceUpdate{}, errors.New(label + " preference changes require a context")
	}
	if s == nil {
		return vprocore.ConfigStringPreferenceUpdate{}, errors.New(label + " preference configuration is unavailable")
	}
	if expected != proposed {
		if err := ValidateReportTitle(fieldLabel, proposed); err != nil {
			return vprocore.ConfigStringPreferenceUpdate{}, err
		}
	}
	return s.CompareAndSetReportStrings(ctx, label+" preferences", []vprocore.ReportStringPreferenceChange{
		{Key: key, Expected: expected, Proposed: proposed},
	})
}

// PreferencesService provides a single generic YAML report-preference read/CAS handler
// shared across report domains (ENG-GO-009).
type PreferencesService[Req any, Rev any] struct {
	Contexts   *vprocore.ContextService
	Snapshot   vprocore.PublicationReadSnapshotHooks
	Label      string
	CheckScope func(string) error
	ReadFn     func(ctx context.Context, contextID string, plots *vprocore.PlotService, owner *vprocore.SqliteContext, tx *sql.Tx) (*Rev, error)
	BeforeFn   func(owner *vprocore.SqliteContext, tx *sql.Tx, request Req) error
	WriteFn    func(ctx context.Context, contextID string, plots *vprocore.PlotService, request Req) (vprocore.ReportPreferenceUpdate, error)
}

func (s *PreferencesService[Req, Rev]) Helper() vprocore.ReportPreferenceHelper {
	if s == nil {
		return vprocore.ReportPreferenceHelper{}
	}
	return vprocore.ReportPreferenceHelper{
		Contexts:   s.Contexts,
		Snapshot:   s.Snapshot,
		CheckScope: s.CheckScope,
	}
}

func (s *PreferencesService[Req, Rev]) Get(ctx context.Context, contextID string) (*Rev, error) {
	if s == nil || s.ReadFn == nil {
		return nil, errors.New("report preference service is unavailable")
	}
	return vprocore.GetOwnedReportPreferences(ctx, s.Helper(), contextID, s.Label,
		func(plots *vprocore.PlotService, owner *vprocore.SqliteContext, tx *sql.Tx) (*Rev, error) {
			return s.ReadFn(ctx, contextID, plots, owner, tx)
		})
}

func (s *PreferencesService[Req, Rev]) SaveJSON(ctx context.Context, contextID, requestJSON string) vprocore.ReportPreferenceOutcome {
	if s == nil || s.WriteFn == nil {
		return vprocore.ReportPreferenceOutcome{ContextID: contextID, ErrorMessage: "report preference service is unavailable"}
	}
	return vprocore.SaveOwnedReportPreferences(ctx, s.Helper(), contextID, requestJSON, s.Label, s.BeforeFn,
		func(plots *vprocore.PlotService, request Req) (vprocore.ReportPreferenceUpdate, error) {
			return s.WriteFn(ctx, contextID, plots, request)
		})
}
