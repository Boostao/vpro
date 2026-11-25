package vprocore

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

var readOnlyChildCapabilityKinds = []string{"Veg", "Humus", "Mineral", "Other"}

// SqliteReadOnlyFileURI builds a net/url-escaped SQLite file: URI in mode=ro,
// appending &immutable=1 when immutable is true (for read-only mounts/snapshots).
func SqliteReadOnlyFileURI(path string, immutable bool) string {
	uri := sqlutil.SqliteFileURI(path, "ro")
	if immutable {
		return uri + "&immutable=1"
	}
	return uri
}

// OpenReadOnlySQLite opens a single-connection read-only SQLite database handle with
// _query_only=on and optional &immutable=1, preserving net/url URI escaping.
func OpenReadOnlySQLite(ctx context.Context, path string, immutable bool) (*sql.DB, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	dsn := SqliteReadOnlyFileURI(absolute, immutable) + "&_query_only=on&_busy_timeout=5000"
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if err := db.PingContext(ctx); err != nil {
		return nil, errors.Join(err, db.Close())
	}
	return db, nil
}

// NewReadOnlySQLiteContext opens a strictly read-only SqliteContext with all support,
// project, SU, hierarchy, and optional profile databases attached in mode=ro (and &immutable=1
// when immutable is true), creates all canonical temp views, and pre-warms ProjectReadDB,
// headerCaps, and childCaps for low-latency concurrent web reads.
func NewReadOnlySQLiteContext(
	ctx context.Context,
	selection DesktopSelection,
	support map[string]string,
	profile *PlotProfileSource,
	immutable bool,
) (_ *SqliteContext, resultErr error) {
	if ctx == nil {
		ctx = context.Background()
	}
	var profiles []*PlotProfileSource
	if profile != nil {
		profiles = []*PlotProfileSource{profile}
	}
	candidate, err := newSQLiteContext(ctx, selection, support, profiles, true, immutable)
	if err != nil {
		return nil, err
	}
	defer func() {
		if resultErr != nil {
			resultErr = errors.Join(resultErr, candidate.Close())
		}
	}()

	readDB, err := candidate.ProjectReadDatabase(ctx)
	if err != nil {
		return nil, err
	}
	reader := sqlutil.ContextPlotDB{DB: readDB, Ctx: ctx}
	if _, err := candidate.CachedHeaderCapabilities(reader, selection.Project); err != nil {
		return nil, err
	}
	for _, kind := range readOnlyChildCapabilityKinds {
		if _, err := candidate.CachedChildCapabilities(reader, selection.Project, kind); err != nil {
			return nil, err
		}
	}
	return candidate, nil
}

// DiscoverSUsReadOnly discovers all *_SU tables in one SQLite database file strictly
// in read-only mode (honoring immutable=1 when immutable is true).
func DiscoverSUsReadOnly(ctx context.Context, path string, immutable bool) ([]SUInfo, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	resolved, err := ExistingDatabasePath(path)
	if err != nil {
		return nil, err
	}
	database, err := OpenReadOnlySQLite(ctx, resolved, immutable)
	if err != nil {
		return nil, err
	}
	defer database.Close()

	reader := sqlutil.ContextPlotDB{DB: database, Ctx: ctx}
	rows, err := reader.Query("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%_SU'")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var names []string
	for rows.Next() {
		var table string
		if err := rows.Scan(&table); err != nil {
			return nil, err
		}
		if name, ok := strings.CutSuffix(table, "_SU"); ok && ProjectNamePattern.MatchString(name) {
			names = append(names, name)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	slices.Sort(names)

	var hasPolicy bool
	if err := reader.QueryRow("SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '_vpro_su_policy')").Scan(&hasPolicy); err != nil {
		return nil, err
	}

	sus := make([]SUInfo, 0, len(names))
	for _, name := range names {
		su := SUInfo{Name: name, Kind: "ordinary", Path: resolved}
		if hasPolicy {
			err := reader.QueryRow("SELECT kind FROM _vpro_su_policy WHERE table_name = ?", name+"_SU").Scan(&su.Kind)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return nil, err
			}
			if errors.Is(err, sql.ErrNoRows) {
				su.Kind = "ordinary"
			}
		}
		fields, err := reader.Query(`PRAGMA table_info(` + QuoteHeaderIdentifier(name+"_SU") + `)`)
		if err != nil {
			return nil, err
		}
		valid := map[string]bool{}
		if scanErr := func() error {
			defer fields.Close()
			for fields.Next() {
				var index, notNull, primaryKey int
				var field, fieldType string
				var defaultValue sql.NullString
				if err := fields.Scan(&index, &field, &fieldType, &notNull, &defaultValue, &primaryKey); err != nil {
					return err
				}
				upper := strings.ToUpper(fieldType)
				valid[field] = strings.Contains(upper, "CHAR") || strings.Contains(upper, "CLOB") || strings.Contains(upper, "TEXT")
			}
			return fields.Err()
		}(); scanErr != nil {
			return nil, scanErr
		}
		su.Compatible = valid["PlotNumber"] && valid["SiteUnit"] && (su.Kind == "ordinary" || su.Kind == "working")
		sus = append(sus, su)
	}
	return sus, nil
}

// DiscoverHierarchiesReadOnly discovers all *_Hierarchy tables in one SQLite database file
// strictly in read-only mode (honoring immutable=1 when immutable is true).
func DiscoverHierarchiesReadOnly(ctx context.Context, path string, immutable bool) ([]HierarchyInfo, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	resolved, err := ExistingDatabasePath(path)
	if err != nil {
		return nil, err
	}
	database, err := OpenReadOnlySQLite(ctx, resolved, immutable)
	if err != nil {
		return nil, err
	}
	defer database.Close()

	reader := sqlutil.ContextPlotDB{DB: database, Ctx: ctx}
	found, err := inspectHierarchies(reader, filepath.Base(resolved))
	if err != nil {
		return nil, err
	}
	for i := range found {
		found[i].Path = resolved
	}
	slices.SortFunc(found, func(left, right HierarchyInfo) int {
		if order := strings.Compare(left.Name, right.Name); order != 0 {
			return order
		}
		return strings.Compare(left.Path, right.Path)
	})
	return found, nil
}
