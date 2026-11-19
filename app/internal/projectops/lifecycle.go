package projectops

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type NewProjectRequest struct {
	ProjectName       string `json:"projectName"`
	ProjectID         string `json:"projectId,omitempty"`
	ProjectTitle      string `json:"projectTitle,omitempty"`
	PresetID          string `json:"presetId,omitempty"`
	DestinationPath   string `json:"destinationPath,omitempty"`
	ActivateOnSuccess bool   `json:"activateOnSuccess"`
}

func (r *NewProjectRequest) UnmarshalJSON(data []byte) error {
	type plain NewProjectRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

type NewProjectResult struct {
	ProjectName      string                 `json:"projectName"`
	ProjectID        string                 `json:"projectId"`
	ProjectIDDerived bool                   `json:"projectIdDerived,omitempty"`
	ProjectIDNotice  string                 `json:"projectIdNotice,omitempty"`
	DestinationPath  string                 `json:"destinationPath"`
	DestinationSHA   string                 `json:"destinationSha256"`
	Activated        bool                   `json:"activated"`
	State            *vprocore.ProjectState `json:"state,omitempty"`
}

// CreateNewProject creates a canonical VP08 SQLite <Name>.db project from VPro64.USys*Table
// templates, tags all 8 core tables 'VP08' in _table_metadata, inserts initial <Name>_Metadata
// and <Name>_Audit provenance rows, publishes atomically via os.Link without overwriting,
// and optionally switches the active context.
func CreateNewProject(s *vprocore.ContextService, ctx context.Context, contextID string, req NewProjectRequest) (_ NewProjectResult, resultErr error) {
	projectName, err := ValidateProjectName(req.ProjectName)
	if err != nil {
		return NewProjectResult{}, err
	}
	projectID := strings.TrimSpace(req.ProjectID)
	projectIDDerived := false
	projectIDNotice := ""
	if projectID == "" {
		projectID = projectName
		if utf16Len(projectID) > 20 {
			origUnits := utf16Len(projectID)
			projectID = truncateUTF16(projectID, 20)
			projectIDDerived = true
			projectIDNotice = fmt.Sprintf("ProjectName %q (%d UTF-16 code units) exceeded the 20-unit ProjectID limit and was truncated to %q.", projectName, origUnits, projectID)
		}
	}
	if err := validateUTF16Max("Metadata.ProjectID", projectID, 20); err != nil {
		return NewProjectResult{}, err
	}
	if err := validateUTF16Max("Metadata.ProjectTitle", req.ProjectTitle, 255); err != nil {
		return NewProjectResult{}, err
	}

	var preset ProjectMetadataPreset
	hasPreset := false
	if strings.TrimSpace(req.PresetID) != "" {
		var ok bool
		preset, ok = GetProjectMetadataPreset(req.PresetID)
		if !ok {
			return NewProjectResult{}, fmt.Errorf("unknown metadata preset %q", req.PresetID)
		}
		hasPreset = true
	}

	snap, err := inspectContextSnapshot(ctx, s, contextID)
	if err != nil {
		return NewProjectResult{}, err
	}
	resolvedDest, parentInfo, err := resolveNewProjectDestination(filepath.Join(snap.Root, "projects"), projectName, req.DestinationPath, "New project")
	if err != nil {
		return NewProjectResult{}, err
	}

	review, err := s.ReadNewProjectTemplates(ctx, contextID)
	if err != nil {
		return NewProjectResult{}, err
	}
	ddlPlan, err := vprocore.PlanNewProjectDDL(ctx, projectName, review)
	if err != nil {
		return NewProjectResult{}, err
	}
	allSpecsStamp, listsStamp, _, err := readVListsVersionStamps(ctx, snap.VListsPath)
	if err != nil {
		return NewProjectResult{}, err
	}

	tmpFile, err := os.CreateTemp(filepath.Dir(resolvedDest), ".vpro-new-project-*.db")
	if err != nil {
		return NewProjectResult{}, err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)
		}
	}()
	if err := tmpFile.Chmod(0600); err != nil {
		_ = tmpFile.Close()
		return NewProjectResult{}, err
	}
	if err := tmpFile.Close(); err != nil {
		return NewProjectResult{}, err
	}

	sqlDB, err := sqlutil.OpenStagedSQLite(tmpPath, sqlutil.StagedSQLiteOptions{ImmediateTxLock: true})
	if err != nil {
		return NewProjectResult{}, err
	}
	tx, err := sqlutil.BeginStagedTx(ctx, sqlDB)
	if err != nil {
		_ = sqlDB.Close()
		return NewProjectResult{}, err
	}

	buildErr := func() error {
		for _, tblPlan := range ddlPlan.Tables {
			for _, mapping := range tblPlan.Schema {
				if mapping.SQL != nil {
					if _, err := tx.ExecContext(ctx, *mapping.SQL); err != nil {
						return fmt.Errorf("create %s: %w", tblPlan.TargetTable, err)
					}
				}
			}
		}
		if _, err := tx.ExecContext(ctx, `CREATE TABLE "_table_metadata" ("table_name" TEXT PRIMARY KEY, "description" TEXT)`); err != nil {
			return err
		}
		for _, suffix := range vprocore.CoreTables {
			if _, err := tx.ExecContext(ctx, `INSERT INTO "_table_metadata" ("table_name", "description") VALUES (?, 'VP08')`, projectName+"_"+suffix); err != nil {
				return err
			}
		}
		if err := ensureChildIdentityTable(ctx, tx); err != nil {
			return err
		}
		if err := reserveChildID(ctx, tx, projectName+"_Metadata", 1); err != nil {
			return err
		}

		now := time.Now().Format("2006-01-02 15:04:05")
		metaCols := []string{"ID", "ProjectID", "AllSpecs", "TableOfLists", "DateLastEdited"}
		metaVals := []any{int64(1), projectID, allSpecsStamp, listsStamp, now}
		if strings.TrimSpace(req.ProjectTitle) != "" {
			metaCols = append(metaCols, "ProjectTitle")
			metaVals = append(metaVals, req.ProjectTitle)
		}
		if hasPreset {
			metaCols = append(metaCols,
				"EcosysCollectionStandard", "VegCoverMethod", "PlotMethod", "Datum",
				"CoordinatingAgency", "ProponentFunder", "FieldCompanyAgency",
				"GeographicStudyArea", "GeoRefMethod", "CoordinateSystem",
			)
			metaVals = append(metaVals,
				preset.EcosysCollectionStandard, preset.VegCoverMethod, preset.PlotMethod, preset.Datum,
				preset.CoordinatingAgency, preset.ProponentFunder, preset.FieldCompanyAgency,
				preset.GeographicStudyArea, preset.GeoRefMethod, preset.CoordinateSystem,
			)
			for _, col := range coverDescriptionColumns {
				if val, ok := preset.CoverDescriptions[col]; ok {
					metaCols = append(metaCols, col)
					metaVals = append(metaVals, val)
				}
			}
		}
		quotedMetaCols := make([]string, len(metaCols))
		marks := make([]string, len(metaCols))
		for i, c := range metaCols {
			quotedMetaCols[i] = vprocore.QuoteHeaderIdentifier(c)
			marks[i] = "?"
		}
		metaInsertSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)",
			vprocore.QuoteHeaderIdentifier(projectName+"_Metadata"),
			strings.Join(quotedMetaCols, ", "),
			strings.Join(marks, ", "),
		)
		if _, err := tx.ExecContext(ctx, metaInsertSQL, metaVals...); err != nil {
			return fmt.Errorf("insert initial metadata row: %w", err)
		}

		for _, entry := range []struct {
			table string
			after any
		}{
			{"NewProject", nil},
			{"USysAllSpecs", allSpecsStamp},
			{"USysTableOfLists", listsStamp},
		} {
			if _, err := vprocore.RecordAudit(ctx, tx, vprocore.AuditWriteEntry{
				Project:   projectName,
				User:      snap.CurrentUser,
				Table:     entry.table,
				EditWhen:  now,
				AfterEdit: entry.after,
			}); err != nil {
				return err
			}
		}
		return ctx.Err()
	}()
	if buildErr != nil {
		_ = tx.Rollback()
		_ = sqlDB.Close()
		return NewProjectResult{}, buildErr
	}
	if err := sqlutil.CommitStagedTx(ctx, tx); err != nil {
		_ = sqlDB.Close()
		return NewProjectResult{}, err
	}
	if err := sqlDB.Close(); err != nil {
		return NewProjectResult{}, err
	}

	if err := verifyStagedVP08Project(ctx, tmpPath, projectName); err != nil {
		return NewProjectResult{}, err
	}
	if err := publishStagedDatabase(tmpPath, resolvedDest, parentInfo); err != nil {
		return NewProjectResult{}, err
	}
	published = true
	_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)

	shaHex, err := computeFileSHA256(resolvedDest)
	if err != nil {
		return NewProjectResult{}, err
	}
	res := NewProjectResult{
		ProjectName:      projectName,
		ProjectID:        projectID,
		ProjectIDDerived: projectIDDerived,
		ProjectIDNotice:  projectIDNotice,
		DestinationPath:  resolvedDest,
		DestinationSHA:   shaHex,
	}
	if req.ActivateOnSuccess {
		state, swErr := s.SwitchContext(contextID, vprocore.ContextSelection{
			Project:     projectName,
			ProjectPath: resolvedDest,
			SU:          "None",
			Hierarchy:   "None",
		})
		if swErr != nil {
			return res, fmt.Errorf("new project published at %s, but context switch failed: %w", resolvedDest, swErr)
		}
		res.Activated = true
		res.State = &state
	}
	return res, nil
}

var companionProjectSuffixes = []string{"SU", "Hierarchy", "Lump", "Profile", "Herbarium", "Theme"}

func rewriteProjectObjectSQL(originalSQL, oldPrefix, newPrefix, oldTable, newTable string) string {
	unquotedCreate := regexp.MustCompile(`(?i)^(\s*CREATE\s+TABLE\s+)` + regexp.QuoteMeta(oldTable) + `(\b)`)
	normalized := unquotedCreate.ReplaceAllString(originalSQL, "${1}"+vprocore.QuoteHeaderIdentifier(oldTable)+"${2}")
	replacer := strings.NewReplacer(
		vprocore.QuoteHeaderIdentifier(oldTable), vprocore.QuoteHeaderIdentifier(newTable),
		vprocore.QuoteHeaderIdentifier(oldPrefix+"_Env"), vprocore.QuoteHeaderIdentifier(newPrefix+"_Env"),
		oldPrefix+"_", newPrefix+"_",
	)
	return replacer.Replace(normalized)
}

func rewriteProjectIndexSQL(originalSQL, idxName, oldPrefix, newPrefix, oldTable, newTable string) string {
	newIdxName := strings.ReplaceAll(idxName, oldPrefix+"_", newPrefix+"_")
	if newIdxName == idxName {
		newIdxName = newTable + "__" + idxName
	}
	unquotedIdx := regexp.MustCompile(`(?i)^(\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?)` + regexp.QuoteMeta(idxName) + `(\b)`)
	normalized := unquotedIdx.ReplaceAllString(originalSQL, "${1}"+vprocore.QuoteHeaderIdentifier(idxName)+"${2}")
	replacer := strings.NewReplacer(
		vprocore.QuoteHeaderIdentifier(idxName), vprocore.QuoteHeaderIdentifier(newIdxName),
		vprocore.QuoteHeaderIdentifier(oldTable), vprocore.QuoteHeaderIdentifier(newTable),
		vprocore.QuoteHeaderIdentifier(oldPrefix+"_Env"), vprocore.QuoteHeaderIdentifier(newPrefix+"_Env"),
		oldPrefix+"_", newPrefix+"_",
	)
	return replacer.Replace(normalized)
}

func rewriteAuditProjectCells(cols []string, rows [][]rawSQLiteCell, targetProject string) {
	projIdx := -1
	for i, c := range cols {
		if strings.EqualFold(c, "Project") {
			projIdx = i
			break
		}
	}
	if projIdx < 0 {
		return
	}
	targetBytes := []byte(targetProject)
	for i := range rows {
		cp := make([]byte, len(targetBytes))
		copy(cp, targetBytes)
		rows[i][projIdx] = rawSQLiteCell{
			storage: "text",
			bytes:   cp,
		}
	}
}

func verifyStagedVP08Project(ctx context.Context, dbPath, projectName string) error {
	inspected, err := vprocore.InspectFileContext(ctx, dbPath)
	if err != nil {
		return fmt.Errorf("verify staged VP08 SQLite project: %w", err)
	}
	for _, info := range inspected {
		if info.Name == projectName && info.Compatible {
			return nil
		}
	}
	return fmt.Errorf("staged SQLite database did not pass VP08 compatibility validation for project %s", projectName)
}

func publishStagedDatabase(tmpPath, resolvedDest string, expectedParent os.FileInfo) error {
	currentParent, err := os.Stat(filepath.Dir(resolvedDest))
	if err != nil || !os.SameFile(expectedParent, currentParent) {
		return errors.New("destination parent directory changed during staging; publication aborted")
	}
	if err := sqlutil.LinkOrCreateExclusive(tmpPath, resolvedDest); err != nil {
		return fmt.Errorf("atomic no-overwrite link to %s failed: %w", resolvedDest, err)
	}
	return nil
}
