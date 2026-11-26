package main

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/interchange"
	"github.com/boostao/vpro/app/internal/spatial"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type becmasterFilterHTTPRequest struct {
	ContextID            string                          `json:"contextId"`
	Filter               *spatial.BECMasterFilterRequest `json:"filter,omitempty"`
	Mode                 string                          `json:"mode,omitempty"`
	Regions              []string                        `json:"regions,omitempty"`
	ProjectIDs           []string                        `json:"projectIds,omitempty"`
	PublicationIDs       []string                        `json:"publicationIds,omitempty"`
	NWLat                *float64                        `json:"nwLat,omitempty"`
	NWLon                *float64                        `json:"nwLon,omitempty"`
	SELat                *float64                        `json:"seLat,omitempty"`
	SELon                *float64                        `json:"seLon,omitempty"`
	Zones                []string                        `json:"zones,omitempty"`
	Subzones             []string                        `json:"subzones,omitempty"`
	MinYear              *int                            `json:"minYear,omitempty"`
	MaxYear              *int                            `json:"maxYear,omitempty"`
	SuccessionalStatuses []string                        `json:"successionalStatuses,omitempty"`
	StructuralStages     []string                        `json:"structuralStages,omitempty"`
	InPublicationsOnly   bool                            `json:"inPublicationsOnly,omitempty"`
	SitePlotQualities    []string                        `json:"sitePlotQualities,omitempty"`
	VegPlotQualities     []string                        `json:"vegPlotQualities,omitempty"`
	SoilPlotQualities    []string                        `json:"soilPlotQualities,omitempty"`
	LocationAccuracy     string                          `json:"locationAccuracy,omitempty"`
}

func (r becmasterFilterHTTPRequest) toFilterRequest() spatial.BECMasterFilterRequest {
	if r.Filter != nil {
		return *r.Filter
	}
	return spatial.BECMasterFilterRequest{
		Mode:                 r.Mode,
		Regions:              r.Regions,
		ProjectIDs:           r.ProjectIDs,
		PublicationIDs:       r.PublicationIDs,
		NWLat:                r.NWLat,
		NWLon:                r.NWLon,
		SELat:                r.SELat,
		SELon:                r.SELon,
		Zones:                r.Zones,
		Subzones:             r.Subzones,
		MinYear:              r.MinYear,
		MaxYear:              r.MaxYear,
		SuccessionalStatuses: r.SuccessionalStatuses,
		StructuralStages:     r.StructuralStages,
		InPublicationsOnly:   r.InPublicationsOnly,
		SitePlotQualities:    r.SitePlotQualities,
		VegPlotQualities:     r.VegPlotQualities,
		SoilPlotQualities:    r.SoilPlotQualities,
		LocationAccuracy:     r.LocationAccuracy,
	}
}

type becmasterDownloadHTTPRequest struct {
	ContextID              string                          `json:"contextId"`
	Format                 string                          `json:"format"` // "vpro64" | "csv" | "gpkg" | "rds" | "turboveg" | "kml"
	PlotNumbers            []string                        `json:"plotNumbers,omitempty"`
	Filter                 *spatial.BECMasterFilterRequest `json:"filter,omitempty"`
	CRS                    string                          `json:"crs,omitempty"`
	IncludeAttributeTables *bool                           `json:"includeAttributeTables,omitempty"`
	TurboVegFormat         string                          `json:"turbovegFormat,omitempty"`
}

type becmasterDownloadHTTPResponse struct {
	DownloadURL string `json:"downloadUrl"`
	Filename    string `json:"filename"`
	Format      string `json:"format"`
	PlotCount   int    `json:"plotCount"`
	Bytes       int64  `json:"bytes"`
}

func (s *WebServer) acquireHTTPContextLease(ctx context.Context, r *http.Request, contextID string) (*vprocore.ReadOnlyLease, *LoadedSnapshot, error) {
	session, err := s.sessions.GetOrCreate(r.Header.Get("X-VPro-Session"))
	if err != nil {
		return nil, nil, &rpcError{status: http.StatusInternalServerError, message: fmt.Sprintf("initialize session: %v", err)}
	}
	snap := s.currentSnapshot()
	if snap == nil {
		return nil, nil, errServiceUnavailable("snapshot catalog is unavailable", 5)
	}
	if trimmed := strings.TrimSpace(contextID); trimmed != "" {
		lease, err := s.pool.AcquireByContextID(ctx, trimmed, session.Prefs)
		if err != nil {
			return nil, nil, err
		}
		return lease, snap, nil
	}
	sel, ok := session.Selection()
	if !ok {
		sel = snap.DefaultSelection()
	} else if _, found := snap.FindDataset(sel.DatasetID, ""); !found {
		sel = snap.DefaultSelection()
		session.SetSelection(sel)
	}
	lease, err := s.pool.Acquire(ctx, sel, session.Prefs)
	if err != nil {
		return nil, nil, err
	}
	return lease, snap, nil
}

func decodeStrictHTTPJSONBody(r *http.Request, dst any) error {
	limited := io.LimitReader(r.Body, maxRPCRequestBodyBytes+1)
	rawBody, err := io.ReadAll(limited)
	if err != nil {
		return errBadRequest("failed to read request body")
	}
	if len(rawBody) > maxRPCRequestBodyBytes {
		return &rpcError{status: http.StatusRequestEntityTooLarge, message: "request body exceeds maximum allowed size"}
	}
	if len(bytes.TrimSpace(rawBody)) == 0 {
		return nil
	}
	dec := json.NewDecoder(bytes.NewReader(rawBody))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return errBadRequest("invalid JSON request body: %v", err)
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errBadRequest("unexpected trailing JSON data in request body")
	}
	return nil
}

func (s *WebServer) handleBECMasterFilterOptions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	contextID := strings.TrimSpace(r.URL.Query().Get("contextId"))
	lease, _, err := s.acquireHTTPContextLease(r.Context(), r, contextID)
	if err != nil {
		s.router.writeRPCError(w, err)
		return
	}
	defer lease.Release()

	opts, err := spatial.GetBECMasterFilterOptions(r.Context(), lease.Context, lease.ContextID)
	if err != nil {
		s.router.writeRPCError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-cache")
	writeJSON(w, http.StatusOK, opts)
}

func (s *WebServer) handleBECMasterFilter(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req becmasterFilterHTTPRequest
	if err := decodeStrictHTTPJSONBody(r, &req); err != nil {
		s.router.writeRPCError(w, err)
		return
	}
	lease, _, err := s.acquireHTTPContextLease(r.Context(), r, req.ContextID)
	if err != nil {
		s.router.writeRPCError(w, err)
		return
	}
	defer lease.Release()

	res, err := spatial.FilterBECMasterPlots(r.Context(), lease.Context, lease.ContextID, req.toFilterRequest())
	if err != nil {
		s.router.writeRPCError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-cache")
	writeJSON(w, http.StatusOK, res)
}

func (s *WebServer) withServerExportSlot(ctx context.Context, fn func(ctx context.Context) (*becmasterDownloadHTTPResponse, error)) (*becmasterDownloadHTTPResponse, error) {
	timeoutCtx, cancel := context.WithTimeout(ctx, s.cfg.ExportTimeout)
	defer cancel()

	select {
	case s.exportSem <- struct{}{}:
	case <-timeoutCtx.Done():
		if errors.Is(ctx.Err(), context.Canceled) {
			return nil, context.Canceled
		}
		return nil, errServiceUnavailable("export worker pool is busy; please retry shortly", 5)
	}
	s.exportInFlight.Add(1)
	defer func() {
		s.exportInFlight.Add(-1)
		<-s.exportSem
	}()

	return fn(timeoutCtx)
}

func (s *WebServer) handleBECMasterDownload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		writeJSONError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req becmasterDownloadHTTPRequest
	if err := decodeStrictHTTPJSONBody(r, &req); err != nil {
		s.router.writeRPCError(w, err)
		return
	}

	format := strings.ToLower(strings.TrimSpace(req.Format))
	switch format {
	case "vpro64", "csv", "gpkg", "rds", "turboveg", "kml":
	default:
		s.router.writeRPCError(w, errBadRequest("unsupported download format %q (supported: vpro64, csv, gpkg, rds, turboveg, kml)", req.Format))
		return
	}
	if len(req.PlotNumbers) == 0 && req.Filter == nil {
		s.router.writeRPCError(w, errBadRequest("download requires plotNumbers or filter"))
		return
	}

	resp, err := s.withServerExportSlot(r.Context(), func(ctx context.Context) (*becmasterDownloadHTTPResponse, error) {
		lease, snap, err := s.acquireHTTPContextLease(ctx, r, req.ContextID)
		if err != nil {
			return nil, err
		}
		defer lease.Release()

		plotNumbers, err := resolveBECMasterDownloadPlots(ctx, lease, req.PlotNumbers, req.Filter)
		if err != nil {
			return nil, err
		}
		if len(plotNumbers) == 0 {
			return nil, errBadRequest("no plots matched the requested download selection")
		}

		project := lease.Dataset.Project
		var suggestedName string
		switch format {
		case "vpro64":
			suggestedName = project + "-subset.db"
		case "csv":
			suggestedName = project + "-subset-csv.zip"
		case "gpkg":
			suggestedName = project + "-subset.gpkg"
		case "rds":
			suggestedName = project + "-subset.rds"
		case "turboveg":
			ext := ".xml"
			if strings.EqualFold(strings.TrimSpace(req.TurboVegFormat), "sqlite") {
				ext = ".sqlite"
			}
			suggestedName = project + "-subset-turboveg" + ext
		case "kml":
			suggestedName = project + "-subset.kml"
		}

		filename := sanitizeDownloadFilename(suggestedName)
		filePath, dirPath, cleanup, err := s.downloads.MintTempPath(filename)
		if err != nil {
			return nil, err
		}

		var outPath string
		switch format {
		case "vpro64":
			if err := buildFilteredVP08SubsetDB(ctx, lease, snap.Catalog.Immutable, plotNumbers, filePath); err != nil {
				cleanup()
				return nil, err
			}
			outPath = filePath

		case "csv":
			if err := exportFilteredCSVZip(ctx, lease, snap.Manifest.SnapshotID, plotNumbers, filePath); err != nil {
				cleanup()
				return nil, err
			}
			outPath = filePath

		case "kml":
			if err := exportFilteredKML(ctx, lease, plotNumbers, filePath); err != nil {
				cleanup()
				return nil, err
			}
			outPath = filePath

		case "gpkg", "rds", "turboveg":
			outPath, err = s.exportSubsetViaInterchange(ctx, lease, snap, plotNumbers, format, req, dirPath, filePath)
			if err != nil {
				cleanup()
				return nil, err
			}
		}

		info, err := os.Stat(outPath)
		if err != nil {
			cleanup()
			return nil, fmt.Errorf("stat generated subset download: %w", err)
		}

		_, dlURL, safeName, err := s.downloads.Register(outPath, dirPath, filename)
		if err != nil {
			cleanup()
			return nil, err
		}

		return &becmasterDownloadHTTPResponse{
			DownloadURL: dlURL,
			Filename:    safeName,
			Format:      format,
			PlotCount:   len(plotNumbers),
			Bytes:       info.Size(),
		}, nil
	})
	if err != nil {
		s.router.writeRPCError(w, err)
		return
	}

	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, resp)
}

func resolveBECMasterDownloadPlots(
	ctx context.Context,
	lease *vprocore.ReadOnlyLease,
	explicit []string,
	filter *spatial.BECMasterFilterRequest,
) ([]string, error) {
	if len(explicit) == 0 && filter != nil {
		res, err := spatial.FilterBECMasterPlots(ctx, lease.Context, lease.ContextID, *filter)
		if err != nil {
			return nil, err
		}
		return res.PlotNumbers, nil
	}

	// Validate explicit plotNumbers against active scoped project/SU so bogus plot IDs are excluded.
	allRes, err := spatial.FilterBECMasterPlots(ctx, lease.Context, lease.ContextID, spatial.BECMasterFilterRequest{Mode: "all"})
	if err != nil {
		return nil, err
	}
	validSet := make(map[string]bool, len(allRes.PlotNumbers))
	for _, p := range allRes.PlotNumbers {
		validSet[p] = true
	}

	seen := make(map[string]bool, len(explicit))
	out := make([]string, 0, len(explicit))
	for _, p := range explicit {
		if p == "" || !utf8.ValidString(p) || strings.ContainsRune(p, 0) {
			return nil, errBadRequest("invalid plotNumber %q in download request", p)
		}
		if validSet[p] && !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	return out, nil
}

// buildFilteredVP08SubsetDB produces a clean, self-contained, un-WAL'd VP08 SQLite .db
// (journal_mode=DELETE + VACUUM, zero -wal/-shm sidecars) containing only plotNumbers.
func buildFilteredVP08SubsetDB(
	ctx context.Context,
	lease *vprocore.ReadOnlyLease,
	srcImmutable bool,
	plotNumbers []string,
	destPath string,
) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if len(plotNumbers) == 0 {
		return errors.New("filtered VP08 subset requires at least one plot")
	}

	// Ensure empty regular file exists for sqlutil.OpenStagedSQLite (mode=rw).
	if err := os.WriteFile(destPath, nil, 0o600); err != nil {
		return fmt.Errorf("initialize subset database file: %w", err)
	}
	cleanupOnErr := true
	defer func() {
		if cleanupOnErr {
			_ = sqlutil.RemoveSQLiteWithSidecars(destPath)
		}
	}()

	db, err := sqlutil.OpenStagedSQLite(destPath, sqlutil.StagedSQLiteOptions{
		ForeignKeys:   false,
		BusyTimeoutMs: 5000,
	})
	if err != nil {
		return fmt.Errorf("open subset database: %w", err)
	}
	closed := false
	defer func() {
		if !closed {
			_ = db.Close()
		}
	}()

	srcURI := vprocore.SqliteReadOnlyFileURI(lease.Dataset.ProjectPath, srcImmutable)
	if _, err := db.ExecContext(ctx, `ATTACH DATABASE ? AS src`, srcURI); err != nil {
		return fmt.Errorf("attach source snapshot DB: %w", err)
	}
	attached := true
	defer func() {
		if attached && !closed {
			_, _ = db.ExecContext(context.Background(), `DETACH DATABASE src`)
		}
	}()

	if _, err := db.ExecContext(ctx, `CREATE TEMP TABLE _selected_plots (PlotNumber TEXT PRIMARY KEY)`); err != nil {
		return fmt.Errorf("create temp plot filter table: %w", err)
	}
	{
		insTx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		stmt, err := insTx.PrepareContext(ctx, `INSERT OR IGNORE INTO temp._selected_plots (PlotNumber) VALUES (?)`)
		if err != nil {
			_ = insTx.Rollback()
			return err
		}
		for i, p := range plotNumbers {
			if i&511 == 0 {
				if err := ctx.Err(); err != nil {
					_ = stmt.Close()
					_ = insTx.Rollback()
					return err
				}
			}
			if _, err := stmt.ExecContext(ctx, p); err != nil {
				_ = stmt.Close()
				_ = insTx.Rollback()
				return err
			}
		}
		if err := stmt.Close(); err != nil {
			_ = insTx.Rollback()
			return err
		}
		if err := insTx.Commit(); err != nil {
			return err
		}
	}

	project := lease.Dataset.Project
	type tableCopySpec struct {
		suffix   string
		mode     string // "plot" | "admin" | "metadata" | "schema_only"
		optional bool
	}
	specs := []tableCopySpec{
		{suffix: "Env", mode: "plot"},
		{suffix: "Admin", mode: "admin"},
		{suffix: "Veg", mode: "plot"},
		{suffix: "Humus", mode: "plot"},
		{suffix: "Mineral", mode: "plot"},
		{suffix: "Other", mode: "plot"},
		{suffix: "Metadata", mode: "metadata"},
		{suffix: "Audit", mode: "schema_only"},
		{suffix: "TreePlot", mode: "plot", optional: true},
		{suffix: "Trees", mode: "plot", optional: true},
	}

	// Discover table DDL and indexes in src.sqlite_master.
	tableDDL := make(map[string]string)
	tableIndexes := make(map[string][]string)
	{
		rows, err := db.QueryContext(ctx, `SELECT type, name, tbl_name, COALESCE(sql, '') FROM src.sqlite_master WHERE type IN ('table', 'index')`)
		if err != nil {
			return fmt.Errorf("read source sqlite_master: %w", err)
		}
		for rows.Next() {
			var objType, name, tblName, ddl string
			if err := rows.Scan(&objType, &name, &tblName, &ddl); err != nil {
				_ = rows.Close()
				return err
			}
			if ddl == "" {
				continue
			}
			if objType == "table" {
				tableDDL[name] = ddl
			} else if objType == "index" {
				tableIndexes[tblName] = append(tableIndexes[tblName], ddl)
			}
		}
		if err := rows.Close(); err != nil {
			return err
		}
	}

	tx, err := sqlutil.BeginStagedTx(ctx, db)
	if err != nil {
		return err
	}

	copiedTables := make([]string, 0, len(specs))
	qEnv := vprocore.QuoteHeaderIdentifier(project + "_Env")

	for _, sp := range specs {
		if err := ctx.Err(); err != nil {
			_ = tx.Rollback()
			return err
		}
		tblName := project + "_" + sp.suffix
		ddl, exists := tableDDL[tblName]
		if !exists {
			if sp.optional {
				continue
			}
			_ = tx.Rollback()
			return fmt.Errorf("source project missing required VP08 table %s", tblName)
		}
		if _, err := tx.ExecContext(ctx, ddl); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("create subset table %s: %w", tblName, err)
		}

		qTbl := vprocore.QuoteHeaderIdentifier(tblName)
		switch sp.mode {
		case "plot":
			copySQL := fmt.Sprintf(
				`INSERT INTO main.%s SELECT t.* FROM src.%s AS t INNER JOIN temp._selected_plots AS sp ON t."PlotNumber" = sp.PlotNumber AND typeof(t."PlotNumber")='text' AND CAST(t."PlotNumber" AS BLOB)=CAST(sp.PlotNumber AS BLOB)`,
				qTbl, qTbl,
			)
			if _, err := tx.ExecContext(ctx, copySQL); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("copy subset rows for %s: %w", tblName, err)
			}
		case "admin":
			copySQL := fmt.Sprintf(
				`INSERT INTO main.%s SELECT t.* FROM src.%s AS t INNER JOIN temp._selected_plots AS sp ON t."Plot" = sp.PlotNumber AND typeof(t."Plot")='text' AND CAST(t."Plot" AS BLOB)=CAST(sp.PlotNumber AS BLOB)`,
				qTbl, qTbl,
			)
			if _, err := tx.ExecContext(ctx, copySQL); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("copy subset rows for %s: %w", tblName, err)
			}
		case "metadata":
			copySQL := fmt.Sprintf(
				`INSERT INTO main.%s SELECT t.* FROM src.%s AS t WHERE TRIM(COALESCE(CAST(t."ProjectID" AS TEXT), '')) IN (SELECT DISTINCT TRIM(CAST("ProjectID" AS TEXT)) FROM main.%s WHERE "ProjectID" IS NOT NULL AND TRIM(CAST("ProjectID" AS TEXT)) <> '')`,
				qTbl, qTbl, qEnv,
			)
			if _, err := tx.ExecContext(ctx, copySQL); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("copy subset metadata for %s: %w", tblName, err)
			}
		case "schema_only":
			// Intentionally leave _Audit empty in public read-only exports.
		}

		for _, idxDDL := range tableIndexes[tblName] {
			if _, err := tx.ExecContext(ctx, idxDDL); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("create index on subset table %s: %w", tblName, err)
			}
		}
		copiedTables = append(copiedTables, tblName)
	}

	// Preserve _table_metadata ('VP08' stamp) for all copied tables.
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS main._table_metadata (table_name TEXT PRIMARY KEY, description TEXT)`); err != nil {
		_ = tx.Rollback()
		return fmt.Errorf("create _table_metadata: %w", err)
	}
	if _, hasSrcMeta := tableDDL["_table_metadata"]; hasSrcMeta {
		for _, tblName := range copiedTables {
			var desc string
			err := tx.QueryRowContext(ctx, `SELECT COALESCE(description, 'VP08') FROM src._table_metadata WHERE table_name = ?`, tblName).Scan(&desc)
			if err != nil || strings.TrimSpace(desc) == "" {
				desc = "VP08"
			}
			if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO main._table_metadata (table_name, description) VALUES (?, ?)`, tblName, desc); err != nil {
				_ = tx.Rollback()
				return err
			}
		}
	} else {
		for _, tblName := range copiedTables {
			if _, err := tx.ExecContext(ctx, `INSERT OR REPLACE INTO main._table_metadata (table_name, description) VALUES (?, 'VP08')`, tblName); err != nil {
				_ = tx.Rollback()
				return err
			}
		}
	}

	if err := sqlutil.CommitStagedTx(ctx, tx); err != nil {
		return err
	}

	if _, err := db.ExecContext(ctx, `DROP TABLE IF EXISTS temp._selected_plots`); err != nil {
		return err
	}
	if _, err := db.ExecContext(ctx, `DETACH DATABASE src`); err != nil {
		return fmt.Errorf("detach source DB: %w", err)
	}
	attached = false

	// Enforce clean single-file journal_mode=DELETE + VACUUM for VPro64 ODBC compatibility.
	if _, err := db.ExecContext(ctx, `PRAGMA journal_mode = DELETE`); err != nil {
		return fmt.Errorf("set journal_mode=DELETE: %w", err)
	}
	if _, err := db.ExecContext(ctx, `VACUUM`); err != nil {
		return fmt.Errorf("vacuum subset database: %w", err)
	}
	if err := db.Close(); err != nil {
		return err
	}
	closed = true

	// Ensure no residual sidecars exist.
	_ = os.Remove(destPath + "-wal")
	_ = os.Remove(destPath + "-shm")
	cleanupOnErr = false
	return nil
}

func (s *WebServer) exportSubsetViaInterchange(
	ctx context.Context,
	lease *vprocore.ReadOnlyLease,
	snap *LoadedSnapshot,
	plotNumbers []string,
	format string,
	req becmasterDownloadHTTPRequest,
	dirPath string,
	destPath string,
) (string, error) {
	// Stage temporary filtered VP08 .db in a dedicated scratch directory inside dirPath,
	// open a single-slot ReadOnlyContextPool over it + the active snapshot's support DBs,
	// and delegate directly to the canonical interchange exporter.
	scratchDir, err := os.MkdirTemp(dirPath, "subset-db-*")
	if err != nil {
		return "", fmt.Errorf("create subset scratch dir: %w", err)
	}
	defer func() { _ = os.RemoveAll(scratchDir) }()

	subsetDBPath := filepath.Join(scratchDir, lease.Dataset.Project+".db")
	if err := buildFilteredVP08SubsetDB(ctx, lease, snap.Catalog.Immutable, plotNumbers, subsetDBPath); err != nil {
		return "", err
	}

	subsetCatalog := vprocore.SnapshotCatalog{
		Generation:   "subset-" + strconv.FormatInt(time.Now().UnixNano(), 36),
		SnapshotID:   snap.Manifest.SnapshotID,
		PublishedAt:  snap.Manifest.PublishedAt,
		Redacted:     snap.Catalog.Redacted,
		RootDir:      scratchDir,
		SupportPaths: snap.Catalog.SupportPaths,
		Immutable:    false,
		Datasets: []vprocore.SnapshotDataset{
			{
				ID:               lease.Dataset.ID,
				Label:            lease.Dataset.Label,
				Project:          lease.Dataset.Project,
				ProjectPath:      subsetDBPath,
				DefaultSU:        "None",
				DefaultHierarchy: "None",
				PlotCount:        len(plotNumbers),
			},
		},
	}

	subPool, err := vprocore.NewReadOnlyContextPool(subsetCatalog, vprocore.ReadOnlyPoolOptions{
		SlotsPerKey: 1,
		MaxPools:    1,
		SiteCodes:   s.refs.siteCodes,
		ParentCodes: s.refs.parentCodes,
	})
	if err != nil {
		return "", fmt.Errorf("init subset context pool: %w", err)
	}
	defer func() { _ = subPool.Close() }()

	subPrefs, err := vprocore.NewInMemoryDesktopConfig(nil)
	if err != nil {
		return "", err
	}
	subLease, err := subPool.Acquire(ctx, vprocore.SelectionKey{
		DatasetID: lease.Dataset.ID,
		SU:        "None",
		Hierarchy: "None",
	}, subPrefs)
	if err != nil {
		return "", fmt.Errorf("acquire subset context: %w", err)
	}
	defer subLease.Release()

	switch format {
	case "gpkg":
		crs := strings.TrimSpace(req.CRS)
		if crs == "" {
			crs = interchange.CRSEPSG3005
		}
		incAttr := true
		if req.IncludeAttributeTables != nil {
			incAttr = *req.IncludeAttributeTables
		}
		outcome, err := interchange.ExportGeoPackage(subLease.Context, ctx, subLease.ContextID, interchange.GeoPackageExportRequest{
			DestinationPath:        destPath,
			CRS:                    crs,
			IncludeAttributeTables: incAttr,
			IncludeUnlocatedPlots:  true,
		})
		if err != nil {
			return "", err
		}
		return outcome.Path, nil

	case "rds":
		outcome, err := interchange.ExportProjectRDS(subLease.Context, ctx, subLease.ContextID, interchange.RDSExportRequest{
			DestinationPath: destPath,
		})
		if err != nil {
			return "", err
		}
		return outcome.Path, nil

	case "turboveg":
		tvFmt := strings.ToLower(strings.TrimSpace(req.TurboVegFormat))
		if tvFmt == "" {
			tvFmt = interchange.TurboVegFormatXML
		}
		outcome, err := interchange.ExportTurboVeg(subLease.Context, ctx, subLease.ContextID, interchange.TurboVegExportRequest{
			Format:          tvFmt,
			DestinationPath: destPath,
		})
		if err != nil {
			return "", err
		}
		return outcome.Path, nil

	default:
		return "", fmt.Errorf("unsupported interchange subset format %q", format)
	}
}

func formatSQLiteCSVCell(v any) string {
	if v == nil {
		return ""
	}
	switch x := v.(type) {
	case []byte:
		return string(x)
	case string:
		return x
	case int64:
		return strconv.FormatInt(x, 10)
	case float64:
		return strconv.FormatFloat(x, 'g', 15, 64)
	case bool:
		if x {
			return "-1"
		}
		return "0"
	case time.Time:
		return x.UTC().Format(time.RFC3339)
	default:
		return fmt.Sprint(x)
	}
}

func exportFilteredCSVZip(
	ctx context.Context,
	lease *vprocore.ReadOnlyLease,
	snapshotID string,
	plotNumbers []string,
	destPath string,
) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	owner := lease.Context.Projects.Sqlite
	unlock, err := owner.AcquireMutex(ctx)
	if err != nil {
		return err
	}
	defer unlock()

	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	selectedSet := make(map[string]bool, len(plotNumbers))
	for _, p := range plotNumbers {
		selectedSet[p] = true
	}

	outFile, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("create CSV zip %q: %w", destPath, err)
	}
	zw := zip.NewWriter(outFile)
	failed := true
	defer func() {
		if failed {
			_ = zw.Close()
			_ = outFile.Close()
			_ = os.Remove(destPath)
		}
	}()

	project := lease.Dataset.Project
	projectIDSet := make(map[string]bool)

	type csvTableSpec struct {
		suffix    string
		keyCol    string
		orderBy   string
		mode      string // "plot" | "metadata"
		optional  bool
	}
	tables := []csvTableSpec{
		{suffix: "Env", keyCol: "PlotNumber", orderBy: `"PlotNumber" COLLATE NOCASE ASC`, mode: "plot"},
		{suffix: "Admin", keyCol: "Plot", orderBy: `"Plot" COLLATE NOCASE ASC`, mode: "plot"},
		{suffix: "Veg", keyCol: "PlotNumber", orderBy: `"PlotNumber" COLLATE NOCASE ASC, "Species" COLLATE NOCASE ASC, "ID" ASC`, mode: "plot"},
		{suffix: "Humus", keyCol: "PlotNumber", orderBy: `"PlotNumber" COLLATE NOCASE ASC, ` + vprocore.HumusOrderBySQL(`"Horizon"`, `"UpperDepth"`) + `, "ID" ASC`, mode: "plot"},
		{suffix: "Mineral", keyCol: "PlotNumber", orderBy: `"PlotNumber" COLLATE NOCASE ASC, "UpperDepth" ASC, "ID" ASC`, mode: "plot"},
		{suffix: "Other", keyCol: "PlotNumber", orderBy: `"PlotNumber" COLLATE NOCASE ASC, "ID" ASC`, mode: "plot"},
		{suffix: "Metadata", keyCol: "ProjectID", orderBy: `"ProjectID" COLLATE NOCASE ASC`, mode: "metadata"},
	}

	for _, spec := range tables {
		if err := ctx.Err(); err != nil {
			return err
		}
		tblName := project + "_" + spec.suffix
		qTbl := `"project".` + vprocore.QuoteHeaderIdentifier(tblName)

		rows, err := tx.QueryContext(ctx, `SELECT * FROM `+qTbl+` ORDER BY `+spec.orderBy)
		if err != nil {
			if spec.optional {
				continue
			}
			return fmt.Errorf("query %s for CSV export: %w", tblName, err)
		}
		cols, err := rows.Columns()
		if err != nil {
			_ = rows.Close()
			return err
		}

		keyIdx := -1
		projIDIdx := -1
		for i, c := range cols {
			if strings.EqualFold(c, spec.keyCol) {
				keyIdx = i
			}
			if spec.suffix == "Env" && strings.EqualFold(c, "ProjectID") {
				projIDIdx = i
			}
		}

		entryWriter, err := zw.Create(tblName + ".csv")
		if err != nil {
			_ = rows.Close()
			return err
		}
		cw := csv.NewWriter(entryWriter)
		if err := cw.Write(cols); err != nil {
			_ = rows.Close()
			return err
		}

		vals := make([]any, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		rec := make([]string, len(cols))
		rowIdx := 0
		for rows.Next() {
			if rowIdx&511 == 0 {
				if err := ctx.Err(); err != nil {
					_ = rows.Close()
					return err
				}
			}
			rowIdx++
			if err := rows.Scan(ptrs...); err != nil {
				_ = rows.Close()
				return err
			}
			if keyIdx >= 0 {
				keyStr := formatSQLiteCSVCell(vals[keyIdx])
				if spec.mode == "plot" {
					if !selectedSet[keyStr] {
						continue
					}
				} else if spec.mode == "metadata" {
					if !projectIDSet[strings.ToUpper(strings.TrimSpace(keyStr))] {
						continue
					}
				}
			}
			if projIDIdx >= 0 {
				if pid := strings.ToUpper(strings.TrimSpace(formatSQLiteCSVCell(vals[projIDIdx]))); pid != "" {
					projectIDSet[pid] = true
				}
			}
			for i := range cols {
				rec[i] = formatSQLiteCSVCell(vals[i])
			}
			if err := cw.Write(rec); err != nil {
				_ = rows.Close()
				return err
			}
		}
		if err := rows.Err(); err != nil {
			_ = rows.Close()
			return err
		}
		_ = rows.Close()
		cw.Flush()
		if err := cw.Error(); err != nil {
			return err
		}
	}

	// Include README.txt with licence & citation matching BEC_plots_Shiny.
	readmeWriter, err := zw.Create("README.txt")
	if err != nil {
		return err
	}
	readme := fmt.Sprintf(
		"VPro BECMaster Filtered Plot Export\n"+
			"Project: %s\n"+
			"Snapshot: %s\n"+
			"Plots: %d\n"+
			"Exported UTC: %s\n\n"+
			"Licence: %s\n"+
			"Licence URL: %s\n\n"+
			"Citation:\n%s\n",
		project, snapshotID, len(plotNumbers), time.Now().UTC().Format(time.RFC3339),
		defaultLicenceName, defaultLicenceURL, defaultBECMasterCitation,
	)
	if _, err := io.WriteString(readmeWriter, readme); err != nil {
		return err
	}

	if err := zw.Close(); err != nil {
		return err
	}
	if err := outFile.Close(); err != nil {
		return err
	}
	failed = false
	return nil
}

func xmlEscapeString(s string) string {
	var b bytes.Buffer
	_ = xml.EscapeText(&b, []byte(s))
	return b.String()
}

func exportFilteredKML(
	ctx context.Context,
	lease *vprocore.ReadOnlyLease,
	plotNumbers []string,
	destPath string,
) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	owner := lease.Context.Projects.Sqlite
	unlock, err := owner.AcquireMutex(ctx)
	if err != nil {
		return err
	}
	defer unlock()

	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	selectedSet := make(map[string]bool, len(plotNumbers))
	for _, p := range plotNumbers {
		selectedSet[p] = true
	}

	project := lease.Dataset.Project
	qEnv := `"project".` + vprocore.QuoteHeaderIdentifier(project+"_Env")
	rows, err := tx.QueryContext(ctx, `SELECT
		CAST("PlotNumber" AS TEXT),
		COALESCE(CAST("Zone" AS TEXT), ''),
		COALESCE(CAST("SubZone" AS TEXT), ''),
		COALESCE(CAST("SiteSeries" AS TEXT), ''),
		COALESCE(CAST("ProjectID" AS TEXT), ''),
		COALESCE(CAST("FSRegionDistrict" AS TEXT), ''),
		COALESCE(CAST("Date" AS TEXT), ''),
		"Elevation",
		"Latitude",
		"Longitude",
		CAST("UTMZone" AS TEXT),
		"UTMEasting",
		"UTMNorthing"
	FROM `+qEnv+`
	WHERE typeof("PlotNumber")='text'
	ORDER BY "PlotNumber" COLLATE NOCASE ASC`)
	if err != nil {
		return fmt.Errorf("query %s_Env for KML export: %w", project, err)
	}
	defer rows.Close()

	var buf bytes.Buffer
	buf.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	buf.WriteString(`<kml xmlns="http://www.opengis.net/kml/2.2">` + "\n")
	buf.WriteString("<Document>\n")
	fmt.Fprintf(&buf, "  <name>%s BECMaster Subset</name>\n", xmlEscapeString(project))
	fmt.Fprintf(&buf, "  <description>%s</description>\n", xmlEscapeString(defaultBECMasterCitation))

	located := 0
	for rows.Next() {
		if err := ctx.Err(); err != nil {
			return err
		}
		var plotNum, zone, subZone, siteSeries, projectID, regionDist, dateStr string
		var elev sql.NullInt64
		var lat, lon, east, north sql.NullFloat64
		var utmZ sql.NullString
		if err := rows.Scan(&plotNum, &zone, &subZone, &siteSeries, &projectID, &regionDist, &dateStr, &elev, &lat, &lon, &utmZ, &east, &north); err != nil {
			return err
		}
		if !selectedSet[plotNum] {
			continue
		}
		var input spatial.PlotGeodesyInput
		if lat.Valid && !math.IsNaN(lat.Float64) && !math.IsInf(lat.Float64, 0) {
			v := lat.Float64
			input.Latitude = &v
		}
		if lon.Valid && !math.IsNaN(lon.Float64) && !math.IsInf(lon.Float64, 0) {
			v := lon.Float64
			input.Longitude = &v
		}
		if utmZ.Valid && strings.TrimSpace(utmZ.String) != "" {
			v := strings.TrimSpace(utmZ.String)
			input.UTMZone = &v
		}
		if east.Valid && !math.IsNaN(east.Float64) && !math.IsInf(east.Float64, 0) {
			v := east.Float64
			input.UTMEasting = &v
		}
		if north.Valid && !math.IsNaN(north.Float64) && !math.IsInf(north.Float64, 0) {
			v := north.Float64
			input.UTMNorthing = &v
		}

		geod := spatial.EvaluatePlotGeodesy(input)
		var pLat, pLon float64
		hasCoord := false
		if geod.NormalizedLat != nil && geod.NormalizedLon != nil {
			pLat, pLon = *geod.NormalizedLat, *geod.NormalizedLon
			hasCoord = true
		} else if geod.UTMDerivedLat != nil && geod.UTMDerivedLon != nil {
			pLat, pLon = *geod.UTMDerivedLat, *geod.UTMDerivedLon
			hasCoord = true
		}
		if !hasCoord || pLat < -90 || pLat > 90 || pLon < -180 || pLon > 180 {
			continue
		}
		located++

		bgc := strings.TrimSpace(zone) + strings.TrimSpace(subZone)
		if ss := strings.TrimSpace(siteSeries); ss != "" {
			bgc += "/" + ss
		}
		descParts := []string{}
		if bgc != "" {
			descParts = append(descParts, "BGC: "+bgc)
		}
		if strings.TrimSpace(projectID) != "" {
			descParts = append(descParts, "Project: "+strings.TrimSpace(projectID))
		}
		if strings.TrimSpace(regionDist) != "" {
			descParts = append(descParts, "Region/District: "+strings.TrimSpace(regionDist))
		}
		if elev.Valid {
			descParts = append(descParts, fmt.Sprintf("Elevation: %d m", elev.Int64))
		}
		if strings.TrimSpace(dateStr) != "" {
			descParts = append(descParts, "Date: "+strings.TrimSpace(dateStr))
		}

		buf.WriteString("  <Placemark>\n")
		fmt.Fprintf(&buf, "    <name>%s</name>\n", xmlEscapeString(plotNum))
		if len(descParts) > 0 {
			fmt.Fprintf(&buf, "    <description>%s</description>\n", xmlEscapeString(strings.Join(descParts, " | ")))
		}
		fmt.Fprintf(&buf, "    <Point><coordinates>%.6f,%.6f,0</coordinates></Point>\n", pLon, pLat)
		buf.WriteString("  </Placemark>\n")
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if located == 0 {
		return errBadRequest("none of the selected plots have valid coordinates for KML export")
	}

	buf.WriteString("</Document>\n</kml>\n")
	if err := os.WriteFile(destPath, buf.Bytes(), 0o600); err != nil {
		return fmt.Errorf("write filtered KML file: %w", err)
	}
	return nil
}
