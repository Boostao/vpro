package vprocore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/mattn/go-sqlite3"
)

// ErrReadOnlyContext is returned when a mutation or read-write database open is attempted on a read-only SqliteContext.
var ErrReadOnlyContext = errors.New("database context is read-only; mutations are disabled")

type SqliteContext struct {
	mu             sync.Mutex `json:"-" yaml:"-"`
	db             *sql.DB
	conn           *sql.Conn                   `json:"-" yaml:"-"`
	ProjectReadDB  *sql.DB                     `json:"-" yaml:"-"`
	ProjectDB      *sql.DB                     `json:"-" yaml:"-"`
	Selection      DesktopSelection            `json:"-" yaml:"-"`
	ReadOnly       bool                        `json:"-" yaml:"-"`
	Immutable      bool                        `json:"-" yaml:"-"`
	Attachments    map[string]string           `json:"-" yaml:"-"`
	AttachmentInfo map[string]os.FileInfo      `json:"-" yaml:"-"`
	Descriptions   map[string][]map[string]any `json:"-" yaml:"-"`
	Profile        *PlotProfileSource          `json:"-" yaml:"-"`
	profileRole    string
	ProfileWrite   bool `json:"-" yaml:"-"`
	userLogPath    string
	userLogRowID   int64
	userLogUser    string

	capsMu     sync.RWMutex               `json:"-" yaml:"-"`
	capsClosed bool                       `json:"-" yaml:"-"`
	headerCaps map[string]bool            `json:"-" yaml:"-"`
	childCaps  map[string]map[string]bool `json:"-" yaml:"-"`
	closeHooks []func()                   `json:"-" yaml:"-"`
}

// BeginConnReadSnapshot starts a caller-owned read-only snapshot transaction on a pinned
// SQLite connection without binding transaction lifetime to ctx's asynchronous awaitDone watcher.
func BeginConnReadSnapshot(ctx context.Context, conn *sql.Conn) (*sql.Tx, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if conn == nil {
		return nil, errors.New("project context is closed")
	}
	tx, err := conn.BeginTx(context.WithoutCancel(ctx), &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, errors.Join(err, tx.Rollback())
	}
	return tx, nil
}

// BeginReadSnapshot — database/sql discards a pinned SQLite connection when a transaction's context
// is cancelled. Keep cleanup caller-owned; every query still uses the request
// context, and callers must check it before committing the read snapshot.
func (c *SqliteContext) BeginReadSnapshot(ctx context.Context) (*sql.Tx, error) {
	if c == nil {
		return nil, errors.New("project context is closed")
	}
	return BeginConnReadSnapshot(ctx, c.conn)
}

// ProjectReadDatabase returns the pooled read-only project database handle (or the active WAL write pool).
func (c *SqliteContext) ProjectReadDatabase(ctx context.Context) (*sql.DB, error) {
	if c == nil {
		return nil, errors.New("project context is closed")
	}
	return c.projectReadDatabase(ctx)
}

func (c *SqliteContext) projectReadDatabase(ctx context.Context) (*sql.DB, error) {
	if err := sqlutil.AcquireMutexLease(ctx, &c.mu); err != nil {
		return nil, err
	}
	defer c.mu.Unlock()
	return c.projectReadDatabaseLocked(ctx)
}

func (c *SqliteContext) projectReadDatabaseLocked(ctx context.Context) (*sql.DB, error) {
	if c.conn == nil {
		return nil, errors.New("project context is closed")
	}
	if c.ProjectDB != nil {
		return c.ProjectDB, nil
	}
	if c.ProjectReadDB != nil {
		return c.ProjectReadDB, nil
	}
	var (
		db  *sql.DB
		err error
	)
	if c.ReadOnly || c.Immutable {
		dsn := SqliteReadOnlyFileURI(c.Selection.ProjectPath, c.Immutable) + "&_foreign_keys=on&_busy_timeout=5000&_query_only=on"
		db, err = sql.Open("sqlite3", dsn)
	} else {
		db, err = sqlutil.OpenReadOnlyBusySQLite(c.Selection.ProjectPath)
	}
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(4)
	db.SetMaxIdleConns(4)
	if err := db.PingContext(ctx); err != nil {
		return nil, errors.Join(err, db.Close())
	}
	c.ProjectReadDB = db
	return db, nil
}

func cloneBoolMap(src map[string]bool) map[string]bool {
	if src == nil {
		return nil
	}
	dst := make(map[string]bool, len(src))
	for k, v := range src {
		dst[k] = v
	}
	return dst
}

// InvalidateSchemaCache clears cached header and child table capability maps on this context.
func (c *SqliteContext) InvalidateSchemaCache() {
	if c == nil {
		return
	}
	c.capsMu.Lock()
	c.headerCaps = nil
	c.childCaps = nil
	c.capsMu.Unlock()
}

// OnClose registers a callback invoked once when this SqliteContext closes (or immediately if already closed).
func (c *SqliteContext) OnClose(fn func()) {
	if c == nil || fn == nil {
		return
	}
	c.capsMu.Lock()
	if c.capsClosed {
		c.capsMu.Unlock()
		fn()
		return
	}
	c.closeHooks = append(c.closeHooks, fn)
	c.capsMu.Unlock()
}

// CachedHeaderCapabilities returns a defensive clone of the cached header capabilities for the
// active project on this context, falling back to PRAGMA table_info when uncached or on mismatch.
func (c *SqliteContext) CachedHeaderCapabilities(db sqlutil.HeaderDB, project string) (map[string]bool, error) {
	if c == nil || project != c.Selection.Project {
		return HeaderCapabilities(db, project)
	}
	c.capsMu.RLock()
	if !c.capsClosed && c.headerCaps != nil {
		cloned := cloneBoolMap(c.headerCaps)
		c.capsMu.RUnlock()
		return cloned, nil
	}
	c.capsMu.RUnlock()

	caps, err := HeaderCapabilities(db, project)
	if err != nil {
		return nil, err
	}
	c.capsMu.Lock()
	if !c.capsClosed && c.headerCaps == nil {
		c.headerCaps = cloneBoolMap(caps)
	}
	c.capsMu.Unlock()
	return cloneBoolMap(caps), nil
}

// CachedChildCapabilities returns a defensive clone of the cached child column capabilities for
// the active project and kind, falling back to PRAGMA table_info when uncached or on mismatch.
func (c *SqliteContext) CachedChildCapabilities(db sqlutil.HeaderDB, project, kind string) (map[string]bool, error) {
	if c == nil || project != c.Selection.Project {
		return ChildCapabilities(db, project, kind)
	}
	c.capsMu.RLock()
	if !c.capsClosed && c.childCaps != nil {
		if existing, ok := c.childCaps[kind]; ok {
			cloned := cloneBoolMap(existing)
			c.capsMu.RUnlock()
			return cloned, nil
		}
	}
	c.capsMu.RUnlock()

	caps, err := ChildCapabilities(db, project, kind)
	if err != nil {
		return nil, err
	}
	c.capsMu.Lock()
	if !c.capsClosed {
		if c.childCaps == nil {
			c.childCaps = make(map[string]map[string]bool, 4)
		}
		if _, exists := c.childCaps[kind]; !exists {
			c.childCaps[kind] = cloneBoolMap(caps)
		}
	}
	c.capsMu.Unlock()
	return cloneBoolMap(caps), nil
}

func (c *SqliteContext) ProjectDatabase(ctx context.Context) (*sql.DB, error) {
	if c == nil {
		return nil, errors.New("project context is closed")
	}
	if c.ReadOnly {
		return nil, ErrReadOnlyContext
	}
	if err := sqlutil.AcquireMutexLease(ctx, &c.mu); err != nil {
		return nil, err
	}
	defer c.mu.Unlock()
	return c.projectDatabaseLocked(ctx)
}

func (c *SqliteContext) projectDatabaseLocked(ctx context.Context) (*sql.DB, error) {
	if c.ReadOnly {
		return nil, ErrReadOnlyContext
	}
	if c.conn == nil {
		return nil, errors.New("project context is closed")
	}
	if c.ProjectDB != nil {
		return c.ProjectDB, nil
	}
	db, err := sqlutil.OpenWALWriteSQLite(c.Selection.ProjectPath)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(2)
	db.SetMaxIdleConns(2)
	var journalMode string
	if err := db.QueryRowContext(ctx, "PRAGMA journal_mode = WAL;").Scan(&journalMode); err != nil {
		return nil, errors.Join(err, db.Close())
	}
	if !strings.EqualFold(journalMode, "wal") {
		return nil, errors.Join(fmt.Errorf("expected SQLite WAL journal mode, got %q", journalMode), db.Close())
	}
	c.ProjectDB = db
	return db, nil
}

func ExistingDatabasePath(path string) (string, error) {
	if path == "" || !filepath.IsAbs(path) {
		return "", fmt.Errorf("database path must be an explicit absolute path: %q", path)
	}
	absolute, err := filepath.EvalSymlinks(filepath.Clean(path))
	if err != nil {
		return "", fmt.Errorf("resolve database %q: %w", path, err)
	}
	info, err := os.Stat(absolute)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() {
		return "", fmt.Errorf("database path is not a regular file: %s", path)
	}
	return absolute, nil
}

func NewSQLiteContext(ctx context.Context, selection DesktopSelection, support map[string]string, profile ...*PlotProfileSource) (*SqliteContext, error) {
	return newSQLiteContext(ctx, selection, support, profile, false, false)
}

func newSQLiteContext(ctx context.Context, selection DesktopSelection, support map[string]string, profile []*PlotProfileSource, readOnly, immutable bool) (_ *SqliteContext, resultErr error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if len(profile) > 1 {
		return nil, errors.New("one explicit plot-profile source may be selected")
	}
	for _, name := range []string{selection.Project, selection.SU, selection.Hierarchy} {
		if !ProjectNamePattern.MatchString(name) {
			return nil, fmt.Errorf("invalid context family name %q", name)
		}
	}
	db, err := sqlutil.OpenMemorySQLite()
	if err != nil {
		return nil, err
	}
	conn, err := db.Conn(ctx)
	if err != nil {
		db.Close()
		return nil, err
	}
	candidate := &SqliteContext{db: db, conn: conn, Selection: selection, ReadOnly: readOnly, Immutable: immutable,
		Attachments: map[string]string{}, AttachmentInfo: map[string]os.FileInfo{}, Descriptions: map[string][]map[string]any{}}
	defer func() {
		if resultErr != nil {
			resultErr = errors.Join(resultErr, candidate.Close())
		}
	}()
	for _, seed := range DatabaseFamilySeeds {
		path, present := support[seed.Name]
		if !present {
			return nil, fmt.Errorf("required support role %s is not configured", seed.Name)
		}
		if _, err := candidate.Attach(ctx, seed.Name, path); err != nil {
			return nil, err
		}
		for _, table := range seed.tables {
			if err := candidate.requireTable(ctx, seed.Name, table); err != nil {
				return nil, err
			}
		}
	}
	if len(support) != len(DatabaseFamilySeeds) {
		return nil, errors.New("unknown support database role")
	}
	projectPath, err := candidate.Attach(ctx, "project", selection.ProjectPath)
	if err != nil {
		return nil, err
	}
	candidate.Selection.ProjectPath = projectPath
	if err := candidate.validateProject(ctx); err != nil {
		return nil, err
	}
	openValidationRO := func(path string) (*sql.DB, error) {
		if readOnly || immutable {
			return OpenReadOnlySQLite(ctx, path, immutable)
		}
		return sqlutil.OpenReadOnly(path)
	}
	if selection.SU != "None" {
		path, err := candidate.Attach(ctx, "su", selection.SUPath)
		if err != nil {
			return nil, err
		}
		candidate.Selection.SUPath = path
		if err := candidate.requireTable(ctx, "su", selection.SU+"_SU"); err != nil {
			return nil, err
		}
		if err := candidate.RequireColumns(ctx, "su", selection.SU+"_SU", []string{"PlotNumber", "SiteUnit"}); err != nil {
			return nil, err
		}
		database, err := openValidationRO(path)
		if err != nil {
			return nil, err
		}
		err = errors.Join(workingUnitSUAuthorized(database, selection.SU), database.Close())
		if err != nil {
			return nil, err
		}
	} else if selection.SUPath != "" {
		return nil, errors.New("SUPath must be empty when no SU is selected")
	}
	if selection.Hierarchy != "None" {
		path, err := candidate.Attach(ctx, "hierarchy", selection.HierarchyPath)
		if err != nil {
			return nil, err
		}
		candidate.Selection.HierarchyPath = path
		if err := candidate.requireTable(ctx, "hierarchy", selection.Hierarchy+"_Hierarchy"); err != nil {
			return nil, err
		}
		if err := candidate.RequireColumns(ctx, "hierarchy", selection.Hierarchy+"_Hierarchy", []string{"ID", "Name", "Parent", "Level"}); err != nil {
			return nil, err
		}
		database, err := openValidationRO(path)
		if err != nil {
			return nil, err
		}
		valid, checkErr := hierarchyCompatible(database, selection.Hierarchy+"_Hierarchy")
		checkErr = errors.Join(checkErr, database.Close())
		if checkErr != nil {
			return nil, checkErr
		}
		if !valid {
			return nil, errors.New("hierarchy requires integer ID/Parent/Level and text Name")
		}
	} else if selection.HierarchyPath != "" {
		return nil, errors.New("HierarchyPath must be empty when no hierarchy is selected")
	}
	if err := candidate.createViews(ctx); err != nil {
		return nil, err
	}
	if len(profile) == 1 && profile[0] != nil {
		if err := candidate.attachProfile(ctx, profile[0]); err != nil {
			return nil, err
		}
	}
	return candidate, nil
}

func (c *SqliteContext) Attach(ctx context.Context, alias, path string) (string, error) {
	path, err := ExistingDatabasePath(path)
	if err != nil {
		return "", fmt.Errorf("attach %s: %w", alias, err)
	}
	if _, exists := c.Attachments[alias]; exists {
		return "", fmt.Errorf("attachment alias %q is already owned", alias)
	}
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("identify attachment %s: %w", alias, err)
	}
	info, statErr := file.Stat()
	if err := errors.Join(statErr, file.Close()); err != nil {
		return "", fmt.Errorf("capture attachment %s identity: %w", alias, err)
	}
	if _, err := c.conn.ExecContext(ctx, "ATTACH DATABASE ? AS "+QuoteHeaderIdentifier(alias), SqliteReadOnlyFileURI(path, c.Immutable)); err != nil {
		return "", fmt.Errorf("attach %s: %w", alias, err)
	}
	current, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("verify attached %s identity: %w", alias, err)
	}
	if !os.SameFile(info, current) {
		return "", fmt.Errorf("attachment %s identity changed during attach", alias)
	}
	c.Attachments[alias] = path
	c.AttachmentInfo[alias] = info
	rows, err := c.tableDescriptions(ctx, alias)
	if err != nil {
		return "", fmt.Errorf("read %s table descriptions: %w", alias, err)
	}
	c.Descriptions[alias] = rows
	return path, nil
}

func (c *SqliteContext) requireTable(ctx context.Context, alias, table string) error {
	var exists bool
	if err := c.conn.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM "+QuoteHeaderIdentifier(alias)+".sqlite_master WHERE type='table' AND name=?)", table).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return fmt.Errorf("%s.%s is missing a required physical table", alias, table)
	}
	return nil
}

func (c *SqliteContext) columns(ctx context.Context, alias, table string) ([]string, error) {
	rows, err := c.conn.QueryContext(ctx, "PRAGMA "+QuoteHeaderIdentifier(alias)+".table_info("+QuoteHeaderIdentifier(table)+")")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var names []string
	for rows.Next() {
		var index, notNull, primaryKey int
		var name, kind string
		var defaultValue any
		if err := rows.Scan(&index, &name, &kind, &notNull, &defaultValue, &primaryKey); err != nil {
			return nil, err
		}
		names = append(names, name)
	}
	return names, rows.Err()
}

func (c *SqliteContext) RequireColumns(ctx context.Context, alias, table string, required []string) error {
	names, err := c.columns(ctx, alias, table)
	if err != nil {
		return err
	}
	for _, name := range required {
		if !slices.Contains(names, name) {
			return fmt.Errorf("%s.%s is missing required column %s", alias, table, name)
		}
	}
	return nil
}

func (c *SqliteContext) tableDescriptions(ctx context.Context, alias string) ([]map[string]any, error) {
	var exists bool
	if err := c.conn.QueryRowContext(ctx, "SELECT EXISTS(SELECT 1 FROM "+QuoteHeaderIdentifier(alias)+".sqlite_master WHERE type='table' AND name='_table_metadata')").Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, nil
	}
	rows, err := c.conn.QueryContext(ctx, "SELECT * FROM "+QuoteHeaderIdentifier(alias)+"._table_metadata")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	names, err := rows.Columns()
	if err != nil {
		return nil, err
	}
	if !slices.Contains(names, "table_name") || !slices.Contains(names, "description") {
		return nil, errors.New("_table_metadata must contain table_name and description")
	}
	var result []map[string]any
	for rows.Next() {
		values, pointers := make([]any, len(names)), make([]any, len(names))
		for i := range values {
			pointers[i] = &values[i]
		}
		if err := rows.Scan(pointers...); err != nil {
			return nil, err
		}
		row := map[string]any{}
		for i, name := range names {
			row[name] = values[i]
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

func (c *SqliteContext) validateProject(ctx context.Context) error {
	for _, suffix := range CoreTables {
		if err := c.requireTable(ctx, "project", c.Selection.Project+"_"+suffix); err != nil {
			return err
		}
	}
	var versions []any
	for _, row := range c.Descriptions["project"] {
		if row["table_name"] == c.Selection.Project+"_Env" {
			versions = append(versions, row["description"])
		}
	}
	if len(versions) != 1 || versions[0] != "VP08" {
		return fmt.Errorf("project %s requires one unambiguous VP08 Env description; found %v (VP05-07 conversion is unavailable)", c.Selection.Project, versions)
	}
	required := map[string][]string{
		"Admin": {"Plot"},
		"Audit": {"Project", "User", "PlotNumber", "Table", "EditField", "EditWhen", "BeforeEdit", "AfterEdit", "Restore", "Flag", "ID"},
		"Humus": {"ID", "PlotNumber"}, "Mineral": {"ID", "PlotNumber"},
		"Other": {"ID", "PlotNumber"}, "Metadata": {"ID", "ProjectID"},
	}
	for _, field := range HeaderFields {
		if field.Table != "" && field.Column != "" {
			required[field.Table] = append(required[field.Table], field.Column)
		}
	}
	for table, fields := range required {
		if err := c.RequireColumns(ctx, "project", c.Selection.Project+"_"+table, fields); err != nil {
			return err
		}
	}
	return nil
}

func (c *SqliteContext) createView(ctx context.Context, name, query string) (resultErr error) {
	if _, err := c.conn.ExecContext(ctx, "CREATE TEMP VIEW "+QuoteHeaderIdentifier(name)+" AS "+query); err != nil {
		return fmt.Errorf("create temporary %s: %w", name, err)
	}
	rows, err := c.conn.QueryContext(ctx, "SELECT * FROM "+QuoteHeaderIdentifier(name)+" LIMIT 0")
	if err != nil {
		return fmt.Errorf("validate temporary %s: %w", name, err)
	}
	defer func() { resultErr = errors.Join(resultErr, rows.Close()) }()
	return rows.Err()
}

// ExactTextPlotPredicate returns an index-friendly SQLite predicate enforcing
// exact UTF-8 byte equality and 'text' storage class for PlotNumber / Plot keys.
// Callers must bind the plot string twice (once for `col = ?` and once for `CAST(? AS BLOB)`).
func ExactTextPlotPredicate(col string) string {
	return "(" + col + " = ? AND typeof(" + col + ") = 'text' AND CAST(" + col + " AS BLOB) = CAST(? AS BLOB))"
}

// ExactTextPlotJoin returns an index-friendly SQLite join predicate enforcing
// exact UTF-8 byte equality and 'text' storage class across left and right keys.
func ExactTextPlotJoin(left, right string) string {
	return "(" + left + " = " + right + " AND typeof(" + left + ") = 'text' AND typeof(" + right + ") = 'text' AND CAST(" + left + " AS BLOB) = CAST(" + right + " AS BLOB))"
}

func (c *SqliteContext) createViews(ctx context.Context) error {
	relation := func(alias, table string) string {
		return QuoteHeaderIdentifier(alias) + "." + QuoteHeaderIdentifier(table)
	}
	project := func(suffix string) string { return relation("project", c.Selection.Project+"_"+suffix) }
	env := "SELECT DISTINCT env.*, admin.* FROM " + project("Env") + " AS env INNER JOIN " + project("Admin") + " AS admin ON " + ExactTextPlotJoin("env.PlotNumber", "admin.Plot")
	if err := c.createView(ctx, "Filtered_Env", env); err != nil {
		return err
	}
	if c.Selection.SU != "None" {
		env += " WHERE EXISTS(SELECT 1 FROM " + relation("su", c.Selection.SU+"_SU") + " AS su WHERE " + ExactTextPlotJoin("su.PlotNumber", "env.PlotNumber") + ")"
	}
	if err := c.createView(ctx, "USysEnv", env); err != nil {
		return err
	}
	for _, entry := range []struct{ view, suffix string }{
		{"USysVeg", "Veg"}, {"USysHumus", "Humus"}, {"USysMineral", "Mineral"},
		{"USysAuditTrail", "Audit"}, {"USysOther", "Other"}, {"USysMetadata", "Metadata"},
	} {
		if err := c.createView(ctx, entry.view, "SELECT DISTINCT * FROM "+project(entry.suffix)); err != nil {
			return err
		}
	}
	for _, entry := range []struct {
		view            string
		fields, filters []string
	}{
		{"USysVegA", []string{"Cover1", "Cover2", "Cover3", "TotalA", "HeightA", "Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB", "HeightB", "Collected"},
			[]string{"Cover1", "Cover2", "Cover3", "TotalA", "Cover4", "Cover5", "TotalB", "Cover5a", "Cover5b", "Cover5c"}},
		{"USysVegB", []string{"Cover4", "Cover5", "Cover5a", "Cover5b", "Cover5c", "TotalB", "Collected"},
			[]string{"Cover4", "Cover5", "TotalB", "Cover5a", "Cover5b", "Cover5c"}},
		{"USysVegC", []string{"Cover6", "Height6", "Collected"}, []string{"Cover6"}},
		{"USysVegD", []string{"Cover7", "Cover8", "Cover9", "Collected"}, []string{"Cover7", "Cover8", "Cover9"}},
	} {
		fields := append([]string{"ID", "PlotNumber", "Species"}, entry.fields...)
		if err := c.RequireColumns(ctx, "project", c.Selection.Project+"_Veg", append(fields, entry.filters...)); err != nil {
			return err
		}
		for i, field := range fields {
			fields[i] = QuoteHeaderIdentifier(field)
		}
		filters := make([]string, len(entry.filters))
		for i, field := range entry.filters {
			filters[i] = QuoteHeaderIdentifier(field) + " IS NOT NULL"
		}
		if err := c.createView(ctx, entry.view, "SELECT DISTINCT "+strings.Join(fields, ",")+" FROM "+project("Veg")+" WHERE "+strings.Join(filters, " OR ")); err != nil {
			return err
		}
	}
	for _, seed := range DatabaseFamilySeeds {
		if seed.Name == "VPro64" {
			continue
		}
		for _, table := range seed.tables {
			view := table
			if table == "MasterSiteUnitList" {
				view = "USysMasterSiteUnitList"
			} else if table == "UserSiteUnitList" {
				view = "USysUserSiteUnitList"
			}
			if err := c.createView(ctx, view, "SELECT * FROM "+relation(seed.Name, table)); err != nil {
				return err
			}
		}
	}
	if err := c.RequireColumns(ctx, "VLists", "USysAllSpecs", []string{"EnglishName", "CombinedEnglishName"}); err != nil {
		return err
	}
	for _, name := range []string{"MasterSiteUnitList", "MasterUnitList_Hierarchy"} {
		if err := c.createView(ctx, name, "SELECT * FROM USysMasterSiteUnitList UNION SELECT * FROM USysUserSiteUnitList"); err != nil {
			return err
		}
	}
	if c.Selection.SU != "None" {
		if err := c.createView(ctx, "USysSU", "SELECT * FROM "+relation("su", c.Selection.SU+"_SU")); err != nil {
			return err
		}
	}
	if c.Selection.Hierarchy != "None" {
		if err := c.createView(ctx, "USysHierarchy", "SELECT * FROM "+relation("hierarchy", c.Selection.Hierarchy+"_Hierarchy")); err != nil {
			return err
		}
	}
	return nil
}

func (c *SqliteContext) Close() error {
	c.mu.Lock()
	_ = c.endUserLogSessionLocked()
	c.capsMu.Lock()
	c.capsClosed = true
	c.headerCaps = nil
	c.childCaps = nil
	hooks := c.closeHooks
	c.closeHooks = nil
	c.capsMu.Unlock()
	var err error
	if c.conn != nil {
		connErr := errors.Join(c.conn.Close(), c.db.Close())
		var readErr error
		if c.ProjectReadDB != nil {
			readErr = c.ProjectReadDB.Close()
		}
		var projectErr error
		if c.ProjectDB != nil {
			projectErr = c.ProjectDB.Close()
		}
		err = errors.Join(connErr, readErr, projectErr)
		c.conn, c.db = nil, nil
		c.ProjectReadDB = nil
		c.ProjectDB = nil
	}
	c.mu.Unlock()
	for _, fn := range hooks {
		fn()
	}
	return err
}

func isReadOnlyUserLogErr(err error) bool {
	if err == nil {
		return false
	}
	var sqliteErr sqlite3.Error
	if errors.As(err, &sqliteErr) {
		switch sqliteErr.Code {
		case sqlite3.ErrReadonly, sqlite3.ErrPerm, sqlite3.ErrCantOpen:
			return true
		}
	}
	lower := strings.ToLower(err.Error())
	return strings.Contains(lower, "readonly") || strings.Contains(lower, "permission denied")
}

func openWritableVPro64LogDB(ctx context.Context, path string) (*sql.DB, error) {
	if path == "" {
		return nil, nil
	}
	info, err := os.Stat(path)
	if err != nil {
		return nil, nil
	}
	if info.Mode().Perm()&0222 == 0 {
		return nil, nil
	}
	db, err := sqlutil.OpenImmediateLockSQLite(path)
	if err != nil {
		if isReadOnlyUserLogErr(err) {
			return nil, nil
		}
		return nil, err
	}
	var tableExists bool
	if err := db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='USysUserLog' COLLATE BINARY)`).Scan(&tableExists); err != nil || !tableExists {
		_ = db.Close()
		return nil, nil
	}
	cols := map[string]bool{}
	rows, err := db.QueryContext(ctx, `PRAGMA table_info("USysUserLog")`)
	if err != nil {
		_ = db.Close()
		return nil, nil
	}
	defer rows.Close()
	for rows.Next() {
		var cid, notNull, pk int
		var name, colType string
		var dflt sql.NullString
		if scanErr := rows.Scan(&cid, &name, &colType, &notNull, &dflt, &pk); scanErr == nil {
			cols[name] = true
		}
	}
	for _, req := range []string{"User", "InTime", "OutTime", "LocalMachine"} {
		if !cols[req] {
			_ = db.Close()
			return nil, nil
		}
	}
	return db, nil
}

// StartUserLogSession appends an InTime entry to VPro64.USysUserLog for the active session,
// cleanly skipping writes when VPro64.db is read-only or lacks the USysUserLog table.
func (c *SqliteContext) StartUserLogSession(ctx context.Context, user string) error {
	if c == nil || c.ReadOnly {
		return nil
	}
	if ctx == nil {
		ctx = context.Background()
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.startUserLogSessionLocked(ctx, user)
}

func (c *SqliteContext) startUserLogSessionLocked(ctx context.Context, user string) error {
	if c.ReadOnly || c.userLogRowID > 0 {
		return nil
	}
	vpro64Path := c.Attachments["VPro64"]
	db, err := openWritableVPro64LogDB(ctx, vpro64Path)
	if err != nil || db == nil {
		return err
	}
	defer db.Close()

	actor := strings.TrimSpace(user)
	if actor == "" {
		actor = "Admin"
	}
	actor = sqlutil.TruncateUTF16(actor, 50)
	host, _ := os.Hostname()
	host = sqlutil.TruncateUTF16(strings.TrimSpace(host), 50)
	now := time.Now().Format("2006-01-02 15:04:05")

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		if isReadOnlyUserLogErr(err) {
			return nil
		}
		return err
	}
	defer tx.Rollback()
	res, err := tx.ExecContext(ctx,
		`INSERT INTO "USysUserLog" ("User","InTime","OutTime","LocalMachine") VALUES (?,?,NULL,?)`,
		actor, now, host)
	if err != nil {
		if isReadOnlyUserLogErr(err) {
			return nil
		}
		return err
	}
	rowID, err := res.LastInsertId()
	if err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		if isReadOnlyUserLogErr(err) {
			return nil
		}
		return err
	}
	c.userLogPath = vpro64Path
	c.userLogRowID = rowID
	c.userLogUser = actor
	return nil
}

// EndUserLogSession closes the tracked USysUserLog row by recording OutTime on close.
func (c *SqliteContext) EndUserLogSession() error {
	if c == nil || c.ReadOnly {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.endUserLogSessionLocked()
}

func (c *SqliteContext) endUserLogSessionLocked() error {
	if c.ReadOnly || c.userLogRowID == 0 || c.userLogPath == "" {
		return nil
	}
	rowID := c.userLogRowID
	vpro64Path := c.userLogPath
	c.userLogRowID = 0
	c.userLogPath = ""
	c.userLogUser = ""

	ctx := context.Background()
	db, err := openWritableVPro64LogDB(ctx, vpro64Path)
	if err != nil || db == nil {
		return err
	}
	defer db.Close()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		if isReadOnlyUserLogErr(err) {
			return nil
		}
		return err
	}
	defer tx.Rollback()
	now := time.Now().Format("2006-01-02 15:04:05")
	if _, err := tx.ExecContext(ctx,
		`UPDATE "USysUserLog" SET "OutTime" = ? WHERE rowid = ? AND "OutTime" IS NULL`,
		now, rowID); err != nil {
		if isReadOnlyUserLogErr(err) {
			return nil
		}
		return err
	}
	if err := tx.Commit(); err != nil {
		if isReadOnlyUserLogErr(err) {
			return nil
		}
		return err
	}
	return nil
}

// RotateUserLogSession closes any active session row only if user actually changed and opens a new one.
func (c *SqliteContext) RotateUserLogSession(ctx context.Context, user string) {
	if c == nil || c.ReadOnly {
		return
	}
	if ctx == nil {
		ctx = context.Background()
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.ReadOnly || c.userLogRowID == 0 {
		return
	}
	trimmed := sqlutil.TruncateUTF16(strings.TrimSpace(user), 50)
	if trimmed == "" || trimmed == c.userLogUser {
		return
	}
	_ = c.endUserLogSessionLocked()
	_ = c.startUserLogSessionLocked(ctx, user)
}

// TransferUserLogSession moves active USysUserLog session tracking from old context to target on context switch.
func (c *SqliteContext) TransferUserLogSession(target *SqliteContext) {
	if c == nil || target == nil || c == target || c.ReadOnly || target.ReadOnly {
		return
	}
	c.mu.Lock()
	rowID, path, user := c.userLogRowID, c.userLogPath, c.userLogUser
	c.userLogRowID, c.userLogPath, c.userLogUser = 0, "", ""
	c.mu.Unlock()

	target.mu.Lock()
	target.userLogRowID, target.userLogPath, target.userLogUser = rowID, path, user
	target.mu.Unlock()
}
