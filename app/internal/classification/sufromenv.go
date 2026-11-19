package classification

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	suFromEnvHistoryTable = "__VPRO_SUFromEnvHistory"
	suFromEnvHistorySQL   = `CREATE TABLE "__VPRO_SUFromEnvHistory"(ID INTEGER PRIMARY KEY,Created TEXT NOT NULL,Proposal TEXT NOT NULL)`
)

type CreateSUFromEnvFieldsRequest struct {
	Fields                    []string `json:"fields"`                    // e.g. ["Zone", "SubZone", "SiteSeries"]
	Separator                 string   `json:"separator"`                 // e.g. "/" or "-"
	FieldSeparators           []string `json:"fieldSeparators,omitempty"` // optional len(fields)-1 explicit separators, e.g. ["", "/"] for Zone+SubZone+"/"+SiteSeries
	UseBECSlashFormat         bool     `json:"useBecSlashFormat"`         // when true on Zone+SubZone+SiteSeries, formats as Zone+SubZone+"/"+SiteSeries
	Mode                      string   `json:"mode"`                      // "overwrite" | "fill_unassigned_only" | "new_table"
	TargetSUName              string   `json:"targetSuName,omitempty"`    // required when mode == "new_table", optional override otherwise
	Destination               string   `json:"destination,omitempty"`     // "project" (default) | "new_file" (for mode == "new_table")
	FilePath                  string   `json:"filePath,omitempty"`
	ScopeToExistingSURowsOnly bool     `json:"scopeToExistingSuRowsOnly"`
	SkipIncompleteRows        bool     `json:"skipIncompleteRows"` // when true, skip plots where any selected field is blank/NULL
	PreviewOnly               bool     `json:"previewOnly"`
	Activate                  bool     `json:"activate"`
}

func (r *CreateSUFromEnvFieldsRequest) UnmarshalJSON(data []byte) error {
	type plain CreateSUFromEnvFieldsRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type SUFromEnvPlotPreview struct {
	PlotNumber     string `json:"plotNumber"`
	BeforeSiteUnit string `json:"beforeSiteUnit"`
	AfterSiteUnit  string `json:"afterSiteUnit"`
	Action         string `json:"action"` // "insert" | "update" | "preserve_existing" | "skip_blank" | "unchanged"
}

type CreateSUFromEnvFieldsResult struct {
	ContextID      string                 `json:"contextId"`
	Mode           string                 `json:"mode"`
	TargetSU       string                 `json:"targetSu"`
	TableName      string                 `json:"tableName"`
	FilePath       string                 `json:"filePath"`
	PreviewOnly    bool                   `json:"previewOnly"`
	InsertedCount  int                    `json:"insertedCount"`
	UpdatedCount   int                    `json:"updatedCount"`
	PreservedCount int                    `json:"preservedCount"`
	SkippedCount   int                    `json:"skippedCount"`
	UnchangedCount int                    `json:"unchangedCount"`
	Items          []SUFromEnvPlotPreview `json:"items"`
	Activated      bool                   `json:"activated"`
	NewState       *vprocore.ProjectState `json:"newState,omitempty"`
}

func concatenateEnvFieldValues(values []string, fields []string, separator string, fieldSeps []string, useBECSlash bool) (string, bool) {
	trimmed := make([]string, len(values))
	allNonEmpty := true
	anyNonEmpty := false
	for i, v := range values {
		t := strings.TrimSpace(v)
		trimmed[i] = t
		if t == "" {
			allNonEmpty = false
		} else {
			anyNonEmpty = true
		}
	}
	if !anyNonEmpty {
		return "", allNonEmpty
	}

	if len(fieldSeps) == len(values)-1 && len(values) > 1 {
		var b strings.Builder
		for i, val := range trimmed {
			if val == "" {
				continue
			}
			if b.Len() > 0 && i > 0 {
				b.WriteString(fieldSeps[i-1])
			}
			b.WriteString(val)
		}
		return b.String(), allNonEmpty
	}

	if useBECSlash && len(fields) >= 2 &&
		strings.EqualFold(fields[0], "Zone") && strings.EqualFold(fields[1], "SubZone") {
		bgc := trimmed[0] + trimmed[1]
		rest := []string{}
		if bgc != "" {
			rest = append(rest, bgc)
		}
		for i := 2; i < len(trimmed); i++ {
			if trimmed[i] != "" {
				rest = append(rest, trimmed[i])
			}
		}
		sep := separator
		if sep == "" {
			sep = "/"
		}
		return strings.Join(rest, sep), allNonEmpty
	}

	nonEmpty := make([]string, 0, len(trimmed))
	for _, val := range trimmed {
		if val != "" {
			nonEmpty = append(nonEmpty, val)
		}
	}
	return strings.Join(nonEmpty, separator), allNonEmpty
}

type suFromEnvTargetSpec struct {
	mode       string
	dest       string
	targetSU   string
	targetRole string
	targetPath string
}

type envPlotConcat struct {
	plot     string
	computed string
	complete bool
}

type plannedSUFromEnvWrite struct {
	isInsert bool
	plot     string
	unit     string
}

func resolveSUFromEnvTarget(owner *vprocore.SqliteContext, mode string, request CreateSUFromEnvFieldsRequest) (suFromEnvTargetSpec, error) {
	dest := strings.ToLower(strings.TrimSpace(request.Destination))
	if dest == "" {
		if strings.TrimSpace(request.FilePath) != "" {
			dest = "new_file"
		} else {
			dest = "project"
		}
	}
	spec := suFromEnvTargetSpec{mode: mode, dest: dest}
	if mode == "new_table" {
		validatedName, vErr := validateClassificationObjectName(request.TargetSUName, "SU")
		if vErr != nil {
			return suFromEnvTargetSpec{}, vErr
		}
		spec.targetSU = validatedName
		if dest == "new_file" {
			fresh, _, fErr := vprocore.FreshSQLiteDestination(request.FilePath, "SU")
			if fErr != nil {
				return suFromEnvTargetSpec{}, fErr
			}
			spec.targetPath = fresh
		} else {
			spec.targetPath = owner.Selection.ProjectPath
		}
		return spec, nil
	}

	if strings.TrimSpace(request.TargetSUName) != "" && !strings.EqualFold(strings.TrimSpace(request.TargetSUName), owner.Selection.SU) {
		targetSUName := strings.TrimSpace(request.TargetSUName)
		if !vprocore.ProjectNamePattern.MatchString(targetSUName) || strings.EqualFold(targetSUName, "None") {
			return suFromEnvTargetSpec{}, fmt.Errorf("invalid existing SU table name %q", request.TargetSUName)
		}
		spec.targetSU = targetSUName
		spec.targetRole = "project"
		spec.targetPath = owner.Selection.ProjectPath
		return spec, nil
	}

	if owner.Selection.SU == "" || owner.Selection.SU == "None" {
		return suFromEnvTargetSpec{}, errors.New("an active Site Unit (SU) table must be selected for 'overwrite' or 'fill_unassigned_only' mode")
	}
	spec.targetSU = owner.Selection.SU
	spec.targetRole = "su"
	spec.targetPath = owner.Selection.SUPath
	return spec, nil
}

func readSUFromEnvSnapshot(
	ctx context.Context,
	rtx *sql.Tx,
	project string,
	spec suFromEnvTargetSpec,
	request CreateSUFromEnvFieldsRequest,
) ([]envPlotConcat, map[string]*string, error) {
	envCols, err := vprocore.ReadSQLiteStorageColumns(ctx, rtx, "project", project+"_Env")
	if err != nil {
		return nil, nil, err
	}
	adminCols, err := vprocore.ReadSQLiteStorageColumns(ctx, rtx, "project", project+"_Admin")
	if err != nil {
		return nil, nil, err
	}

	envSet := make(map[string]string, len(envCols))
	for _, c := range envCols {
		envSet[strings.ToLower(c.Name)] = c.Name
	}
	adminSet := make(map[string]string, len(adminCols))
	for _, c := range adminCols {
		adminSet[strings.ToLower(c.Name)] = c.Name
	}

	selectExprs := []string{`CAST(env."PlotNumber" AS TEXT)`}
	canonicalFields := make([]string, len(request.Fields))
	for i, rawField := range request.Fields {
		lower := strings.ToLower(strings.TrimSpace(rawField))
		if actual, ok := envSet[lower]; ok {
			canonicalFields[i] = actual
			selectExprs = append(selectExprs, `COALESCE(CAST(env.`+vprocore.QuoteHeaderIdentifier(actual)+` AS TEXT), '')`)
		} else if actual, ok := adminSet[lower]; ok {
			canonicalFields[i] = actual
			selectExprs = append(selectExprs, `COALESCE(CAST(admin.`+vprocore.QuoteHeaderIdentifier(actual)+` AS TEXT), '')`)
		} else {
			return nil, nil, fmt.Errorf("field %q was not found on %s_Env or %s_Admin", rawField, project, project)
		}
	}

	envComputed, err := scanEnvPlotConcatRows(ctx, rtx, project, selectExprs, canonicalFields, request)
	if err != nil {
		return nil, nil, err
	}
	existingSU := map[string]*string{}
	if spec.mode != "new_table" {
		existingSU, err = readExistingSURowMap(ctx, rtx, spec.targetRole, spec.targetSU+"_SU")
		if err != nil {
			return nil, nil, err
		}
	}
	return envComputed, existingSU, nil
}

func scanEnvPlotConcatRows(
	ctx context.Context,
	rtx *sql.Tx,
	project string,
	selectExprs, canonicalFields []string,
	request CreateSUFromEnvFieldsRequest,
) ([]envPlotConcat, error) {
	qSQL := `SELECT ` + strings.Join(selectExprs, ", ") +
		` FROM "project".` + vprocore.QuoteHeaderIdentifier(project+"_Env") + ` AS env` +
		` LEFT JOIN "project".` + vprocore.QuoteHeaderIdentifier(project+"_Admin") + ` AS admin` +
		` ON admin."Plot" = env."PlotNumber" AND typeof(env."PlotNumber")='text' AND typeof(admin."Plot")='text'` +
		` AND CAST(env."PlotNumber" AS BLOB)=CAST(admin."Plot" AS BLOB)` +
		` WHERE env."PlotNumber" IS NOT NULL AND TRIM(CAST(env."PlotNumber" AS TEXT)) <> ''` +
		` ORDER BY env."PlotNumber" COLLATE NOCASE ASC, env.rowid ASC`
	rows, err := rtx.QueryContext(ctx, qSQL)
	if err != nil {
		return nil, err
	}
	var envComputed []envPlotConcat
	seenEnvPlot := map[string]bool{}
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, rows.Close()) }()
		for rows.Next() {
			vals := make([]string, len(request.Fields)+1)
			ptrs := make([]any, len(vals))
			for i := range vals {
				ptrs[i] = &vals[i]
			}
			if sErr := rows.Scan(ptrs...); sErr != nil {

				return sErr
			}
			plotNum := vals[0]
			if seenEnvPlot[plotNum] || len(utf16.Encode([]rune(plotNum))) > 7 {
				continue
			}
			seenEnvPlot[plotNum] = true
			unitStr, complete := concatenateEnvFieldValues(vals[1:], canonicalFields, request.Separator, request.FieldSeparators, request.UseBECSlashFormat)
			if len(utf16.Encode([]rune(unitStr))) > 255 {

				return fmt.Errorf("concatenated SiteUnit for plot %q cannot exceed 255 characters (%q)", plotNum, unitStr)
			}
			envComputed = append(envComputed, envPlotConcat{plot: plotNum, computed: unitStr, complete: complete})
		}
		return rows.Err()
	}(); err != nil {
		return nil, err
	}
	return envComputed, nil
}

func readExistingSURowMap(ctx context.Context, rtx *sql.Tx, targetRole, suTableName string) (map[string]*string, error) {
	var exists bool
	if err := rtx.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM `+vprocore.QuoteHeaderIdentifier(targetRole)+`.sqlite_master WHERE type='table' AND name COLLATE BINARY=?)`,
		suTableName,
	).Scan(&exists); err != nil || !exists {
		return nil, fmt.Errorf("existing SU table %s not found in %s database", suTableName, targetRole)
	}
	sRows, err := rtx.QueryContext(ctx,
		`SELECT CAST("PlotNumber" AS TEXT), CAST("SiteUnit" AS TEXT) FROM `+
			vprocore.QuoteHeaderIdentifier(targetRole)+`.`+vprocore.QuoteHeaderIdentifier(suTableName)+` WHERE typeof("PlotNumber")='text' ORDER BY rowid ASC`)
	if err != nil {
		return nil, err
	}
	existingSU := map[string]*string{}
	if err := func() (scanErr error) {
		defer func() { scanErr = errors.Join(scanErr, sRows.Close()) }()
		for sRows.Next() {
			var p, u sql.NullString
			if err := sRows.Scan(&p, &u); err != nil {

				return err
			}
			if !p.Valid || strings.TrimSpace(p.String) == "" {
				continue
			}
			if u.Valid && strings.TrimSpace(u.String) != "" {
				val := strings.TrimSpace(u.String)
				existingSU[p.String] = &val
			} else {
				existingSU[p.String] = nil
			}
		}
		return sRows.Err()
	}(); err != nil {
		return nil, err
	}
	return existingSU, nil
}

func planSUFromEnvWrites(
	contextID string,
	spec suFromEnvTargetSpec,
	request CreateSUFromEnvFieldsRequest,
	envComputed []envPlotConcat,
	existingSU map[string]*string,
) (*CreateSUFromEnvFieldsResult, []plannedSUFromEnvWrite) {
	out := &CreateSUFromEnvFieldsResult{
		ContextID:   contextID,
		Mode:        spec.mode,
		TargetSU:    spec.targetSU,
		TableName:   spec.targetSU + "_SU",
		FilePath:    spec.targetPath,
		PreviewOnly: request.PreviewOnly,
		Items:       make([]SUFromEnvPlotPreview, 0, len(envComputed)),
	}
	var writes []plannedSUFromEnvWrite
	for _, item := range envComputed {
		presentInSU := false
		var prevUnit *string
		if spec.mode != "new_table" {
			prevUnit, presentInSU = existingSU[item.plot]
			if request.ScopeToExistingSURowsOnly && !presentInSU {
				continue
			}
		}
		beforeStr := ""
		if prevUnit != nil {
			beforeStr = *prevUnit
		}
		if spec.mode == "fill_unassigned_only" && presentInSU && beforeStr != "" {
			out.PreservedCount++
			out.Items = append(out.Items, SUFromEnvPlotPreview{
				PlotNumber: item.plot, BeforeSiteUnit: beforeStr, AfterSiteUnit: beforeStr, Action: "preserve_existing",
			})
			continue
		}
		if item.computed == "" || (request.SkipIncompleteRows && !item.complete) {
			out.SkippedCount++
			out.Items = append(out.Items, SUFromEnvPlotPreview{
				PlotNumber: item.plot, BeforeSiteUnit: beforeStr, AfterSiteUnit: beforeStr, Action: "skip_blank",
			})
			continue
		}
		if spec.mode == "new_table" || !presentInSU {
			out.InsertedCount++
			out.Items = append(out.Items, SUFromEnvPlotPreview{
				PlotNumber: item.plot, BeforeSiteUnit: "", AfterSiteUnit: item.computed, Action: "insert",
			})
			writes = append(writes, plannedSUFromEnvWrite{isInsert: true, plot: item.plot, unit: item.computed})
		} else if beforeStr == item.computed {
			out.UnchangedCount++
			out.Items = append(out.Items, SUFromEnvPlotPreview{
				PlotNumber: item.plot, BeforeSiteUnit: beforeStr, AfterSiteUnit: item.computed, Action: "unchanged",
			})
		} else {
			out.UpdatedCount++
			out.Items = append(out.Items, SUFromEnvPlotPreview{
				PlotNumber: item.plot, BeforeSiteUnit: beforeStr, AfterSiteUnit: item.computed, Action: "update",
			})
			writes = append(writes, plannedSUFromEnvWrite{isInsert: false, plot: item.plot, unit: item.computed})
		}
	}
	return out, writes
}

func commitStandaloneSUFromEnvFile(ctx context.Context, spec suFromEnvTargetSpec, writes []plannedSUFromEnvWrite, proposal string) error {
	committed := false
	db, err := sqlutil.OpenWALCreateSQLite(spec.targetPath)
	if err != nil {
		return err
	}
	defer func() {
		_ = db.Close()
		if !committed {
			_ = os.Remove(spec.targetPath)
		}
	}()
	wtx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() {
		if !committed {
			_ = wtx.Rollback()
		}
	}()
	if err := createSUTableObjectsInTx(ctx, wtx, spec.targetSU); err != nil {
		return err
	}
	qTarget := vprocore.QuoteHeaderIdentifier(spec.targetSU + "_SU")
	for _, w := range writes {
		if _, err := wtx.ExecContext(ctx, `INSERT INTO main.`+qTarget+` ("PlotNumber","SiteUnit") VALUES (?,?)`, w.plot, w.unit); err != nil {
			return err
		}
	}
	if err := vprocore.AppendTechnicalProvenance(ctx, wtx, suFromEnvHistoryTable, suFromEnvHistorySQL, proposal, "create SU from Env fields"); err != nil {
		return err
	}
	if err := wtx.Commit(); err != nil {
		return err
	}
	committed = true
	return nil
}

func commitAttachedSUFromEnvTable(
	ctx context.Context,
	owner *vprocore.SqliteContext,
	spec suFromEnvTargetSpec,
	writes []plannedSUFromEnvWrite,
	proposal string,
) error {
	writerRole := spec.targetRole
	if spec.mode == "new_table" {
		writerRole = "project"
	}
	validateFiles := func() error {
		if err := owner.ValidateMetadataWriterFiles(); err != nil {
			return err
		}
		info := owner.AttachmentInfo[writerRole]
		if info == nil {
			return fmt.Errorf("target role %s is unavailable", writerRole)
		}
		for role, sInfo := range owner.AttachmentInfo {
			if strings.HasPrefix(role, "V") && os.SameFile(info, sInfo) {
				return fmt.Errorf("target database shares a file with support role %s", role)
			}
		}
		return nil
	}
	return owner.WithImmediateRoleWriteTx(ctx, writerRole, validateFiles, func(wtx *vprocore.WriteTx) error {
		if spec.mode == "new_table" {
			if err := createSUTableObjectsInTx(ctx, wtx.Tx, spec.targetSU); err != nil {
				return err
			}
		}
		qTarget := vprocore.QuoteHeaderIdentifier(spec.targetSU + "_SU")
		for _, w := range writes {
			if err := ctx.Err(); err != nil {
				return err
			}
			if w.isInsert {
				if _, err := wtx.ExecContext(ctx, `INSERT INTO main.`+qTarget+` ("PlotNumber","SiteUnit") VALUES (?,?)`, w.plot, w.unit); err != nil {
					return err
				}
			} else {
				updSQL := `UPDATE main.` + qTarget + ` SET "SiteUnit" = ? WHERE "PlotNumber" = ? AND typeof("PlotNumber")='text' AND CAST("PlotNumber" AS BLOB)=CAST(? AS BLOB)`
				if spec.mode == "fill_unassigned_only" {
					updSQL += ` AND ("SiteUnit" IS NULL OR TRIM("SiteUnit") = '')`
				}
				if _, err := wtx.ExecContext(ctx, updSQL, w.unit, w.plot, w.plot); err != nil {
					return err
				}
			}
		}
		if len(writes) > 0 || spec.mode == "new_table" {
			if err := vprocore.AppendTechnicalProvenance(ctx, wtx.Tx, suFromEnvHistoryTable, suFromEnvHistorySQL, proposal, "SU from Env fields"); err != nil {
				return err
			}
		}
		return validateFiles()
	})
}

// CreateSUFromEnvFields populates Site Units from concatenated _Env/_Admin columns,
// supporting both creating a new *_SU table and updating/filling an existing *_SU table
// (modes: "overwrite" | "fill_unassigned_only" | "new_table", per VPro2.0_Functions p. 6 P021).
func CreateSUFromEnvFields(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	request CreateSUFromEnvFieldsRequest,
) (*CreateSUFromEnvFieldsResult, error) {
	if ctx == nil {
		return nil, errors.New("CreateSUFromEnvFields requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	if len(request.Fields) == 0 || len(request.Fields) > 10 {
		return nil, errors.New("select between 1 and 10 Env/Admin fields to concatenate")
	}
	if !utf8.ValidString(request.Separator) || strings.ContainsRune(request.Separator, 0) {
		return nil, errors.New("separator must be valid UTF-8 without NUL")
	}
	mode := strings.ToLower(strings.TrimSpace(request.Mode))
	if mode != "overwrite" && mode != "fill_unassigned_only" && mode != "new_table" {
		return nil, fmt.Errorf("unsupported mode %q; expected 'overwrite', 'fill_unassigned_only', or 'new_table'", request.Mode)
	}

	var result *CreateSUFromEnvFieldsResult
	var currentSelection vprocore.DesktopSelection

	_, err := vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		owner := plots.Projects.Sqlite
		currentSelection = owner.Selection
		project := owner.Selection.Project

		spec, err := resolveSUFromEnvTarget(owner, mode, request)
		if err != nil {
			return struct{}{}, err
		}

		var envComputed []envPlotConcat
		var existingSU map[string]*string
		if err := owner.WithReadSnapshot(ctx, func(rtx *sql.Tx) error {
			var snapErr error
			envComputed, existingSU, snapErr = readSUFromEnvSnapshot(ctx, rtx, project, spec, request)
			return snapErr
		}); err != nil {
			return struct{}{}, err
		}

		out, writes := planSUFromEnvWrites(contextID, spec, request, envComputed, existingSU)
		if request.PreviewOnly {
			result = out
			return struct{}{}, nil
		}

		proposalBytes, err := json.Marshal(request)
		if err != nil {
			return struct{}{}, err
		}
		if spec.mode == "new_table" && spec.dest == "new_file" {
			if err := commitStandaloneSUFromEnvFile(ctx, spec, writes, string(proposalBytes)); err != nil {
				return struct{}{}, err
			}
		} else {
			if err := commitAttachedSUFromEnvTable(ctx, owner, spec, writes, string(proposalBytes)); err != nil {
				return struct{}{}, err
			}
		}
		result = out
		return struct{}{}, nil
	})
	if err != nil {
		return nil, err
	}

	if !request.PreviewOnly && request.Activate && (mode == "new_table" || !strings.EqualFold(result.TargetSU, currentSelection.SU)) {
		nextState, swErr := contexts.SwitchContext(contextID, vprocore.ContextSelection{
			Project:       currentSelection.Project,
			ProjectPath:   currentSelection.ProjectPath,
			SU:            result.TargetSU,
			SUPath:        result.FilePath,
			Hierarchy:     currentSelection.Hierarchy,
			HierarchyPath: currentSelection.HierarchyPath,
		})
		if swErr != nil {
			return nil, swErr
		}
		result.Activated = true
		result.ContextID = nextState.ContextID
		result.NewState = &nextState
	}
	return result, nil
}
