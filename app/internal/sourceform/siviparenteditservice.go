package sourceform

import (
	"context"
	"errors"
	"fmt"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type SIVIParentDirectWrite struct {
	Original    *SourceParentProjection `json:"original"`
	Scalars     []SourceParentCellEdit  `json:"scalars"`
	Options     []SourceParentCellEdit  `json:"options"`
	Text        []SourceParentCellEdit  `json:"text"`
	Categorical []SourceParentCellEdit  `json:"categorical"`
}

func (edit *SourceParentCellEdit) UnmarshalJSON(data []byte) error {
	type plain SourceParentCellEdit
	var decoded plain
	if err := vprocore.DecodeProfileLifecycleJSON(data, &decoded, "contextId", "table", "rowId", "column", "expected", "value"); err != nil {
		return fmt.Errorf("SIVI parent direct-cell transport: %w", err)
	}
	*edit = SourceParentCellEdit(decoded)
	return nil
}

func (request *SIVIParentDirectWrite) UnmarshalJSON(data []byte) error {
	type plain SIVIParentDirectWrite
	var decoded plain
	if err := vprocore.DecodeProfileLifecycleJSON(data, &decoded, "original", "scalars", "options", "text", "categorical"); err != nil {
		return fmt.Errorf("SIVI parent direct-write transport: %w", err)
	}
	*request = SIVIParentDirectWrite(decoded)
	return nil
}

func RequireSIVIParentEditing(s *vprocore.ContextService, ctx context.Context) error {
	if ctx == nil {
		return errors.New("SIVI parent editing requires a context")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if s == nil {
		return errors.New("SIVI parent editing requires owned contexts")
	}
	return nil
}

func SaveSIVIParentDirect(s *vprocore.ContextService, ctx context.Context, contextID, plot string, request SIVIParentDirectWrite) (*SourceParentWriteResult, error) {
	if err := RequireSIVIParentEditing(s, ctx); err != nil {
		return nil, err
	}
	return WriteSIVIParentDirect(s, ctx, contextID, plot, request.Original,
		SiviParentDirectEdits{request.Scalars, request.Options, request.Text, request.Categorical})
}

func GetSIVIParentDirectOriginal(s *vprocore.ContextService, ctx context.Context, contextID, plot string) (*SourceParentProjection, error) {
	if err := RequireSIVIParentEditing(s, ctx); err != nil {
		return nil, err
	}
	return ReadSIVIParent(s, ctx, contextID, plot)
}

func RestoreSIVIParentDirect(s *vprocore.ContextService, ctx context.Context, contextID, plot, historyID string, action vprocore.AuditRestoreAction) (*vprocore.AuditRestoreResult, error) {
	if err := RequireSIVIParentEditing(s, ctx); err != nil {
		return nil, err
	}
	return CtxRestoreSIVIParentDirect(s, ctx, contextID, plot, historyID, action)
}
