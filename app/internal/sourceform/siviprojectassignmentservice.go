package sourceform

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type SIVIProjectAssignmentOriginal struct {
	Original             *SourceParentProjection
	Choices              *SourceProjectChoices
	AssignmentAvailable  bool
	AssignmentDiagnostic string
}

type SIVIProjectSelection struct {
	ContextID        string                           `json:"contextId"`
	ControlID        string                           `json:"controlId"`
	Table            string                           `json:"table"`
	RowID            string                           `json:"rowId"`
	Expected         vprocore.ProjectMetadataCell     `json:"expected"`
	SourceOption     int                              `json:"sourceOption"`
	MetadataAlias    string                           `json:"metadataAlias"`
	MetadataTable    string                           `json:"metadataTable"`
	MetadataColumns  []vprocore.ProjectMetadataColumn `json:"metadataColumns"`
	MetadataOriginal vprocore.ProjectMetadataRow      `json:"metadataOriginal"`
}

type SourceProjectSelection = SIVIProjectSelection

type SIVIProjectAssignmentWrite struct {
	Original  *SourceParentProjection `json:"original"`
	Selection SourceProjectSelection  `json:"selection"`
}

func (input *SourceProjectSelection) UnmarshalJSON(data []byte) error {
	type plain SourceProjectSelection
	var decoded plain
	if err := vprocore.DecodeProfileLifecycleJSON(data, &decoded, "contextId", "controlId", "table", "rowId",
		"expected", "sourceOption", "metadataAlias", "metadataTable", "metadataColumns", "metadataOriginal"); err != nil {
		return fmt.Errorf("SIVI ProjectID selection transport: %w", err)
	}
	var properties map[string]json.RawMessage
	if err := json.Unmarshal(data, &properties); err != nil {
		return err
	}
	if err := vprocore.DecodeProfileLifecycleJSON(properties["metadataOriginal"], &decoded.MetadataOriginal, "rowId", "cells"); err != nil {
		return fmt.Errorf("SIVI ProjectID metadata row transport: %w", err)
	}
	var columns []json.RawMessage
	if err := json.Unmarshal(properties["metadataColumns"], &columns); err != nil {
		return err
	}
	for index, raw := range columns {
		if err := vprocore.DecodeProfileLifecycleJSON(raw, &decoded.MetadataColumns[index], "name", "declaredType"); err != nil {
			return fmt.Errorf("SIVI ProjectID metadata column transport: %w", err)
		}
	}
	*input = SourceProjectSelection(decoded)
	return nil
}

func (request *SIVIProjectAssignmentWrite) UnmarshalJSON(data []byte) error {
	type plain SIVIProjectAssignmentWrite
	var decoded plain
	if err := vprocore.DecodeProfileLifecycleJSON(data, &decoded, "original", "selection"); err != nil {
		return fmt.Errorf("SIVI ProjectID assignment transport: %w", err)
	}
	*request = SIVIProjectAssignmentWrite(decoded)
	return nil
}

func (input SourceProjectSelection) Private() SourceProjectSelectionInternal {
	return SourceProjectSelectionInternal(input)
}

func RequireSIVIProjectAssignment(s *vprocore.ContextService, ctx context.Context) error {
	return RequireSIVIParentEditing(s, ctx)
}

func GetSIVIProjectAssignmentOriginal(s *vprocore.ContextService, ctx context.Context, contextID, plot string) (*SIVIProjectAssignmentOriginal, error) {
	if err := RequireSIVIProjectAssignment(s, ctx); err != nil {
		return nil, err
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (*SIVIProjectAssignmentOriginal, error) {
		values, err := plots.Projects.Preferences.Snapshot()
		if err != nil {
			return nil, err
		}
		source, err := vprocore.ConfigInt(values, "Current", "ProjectIdSource", 1, 2)
		if err != nil {
			return nil, fmt.Errorf("SIVI ProjectID assignment source unavailable: %w", err)
		}
		return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*SIVIProjectAssignmentOriginal, error) {
			return readSIVIProjectAssignmentSnapshot(ctx, owner, tx, contextID, plot, source)
		})
	})
}

func SaveSIVIProjectAssignment(s *vprocore.ContextService, ctx context.Context, contextID, plot string, request SIVIProjectAssignmentWrite) (*SourceParentWriteResult, error) {
	if err := RequireSIVIProjectAssignment(s, ctx); err != nil {
		return nil, err
	}
	return WriteSIVIProjectAssignment(s, ctx, contextID, plot, request.Original, request.Selection.Private())
}

func RestoreSIVIProjectAssignment(s *vprocore.ContextService, ctx context.Context, contextID, plot, historyID string, action vprocore.AuditRestoreAction) (*vprocore.AuditRestoreResult, error) {
	if err := RequireSIVIProjectAssignment(s, ctx); err != nil {
		return nil, err
	}
	return CtxRestoreSIVIProjectAssignment(s, ctx, contextID, plot, historyID, action)
}
